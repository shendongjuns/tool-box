import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { migrations, SCHEMA_VERSION } from "../migrations.js";
import { createBackup } from "../backup.js";
import * as schema from "../schema.js";
import type { AppDatabase } from "../types.js";

export interface NodeDatabase {
  db: AppDatabase;
  raw: Database.Database;
  /** 本次启动执行过的迁移（空表示无需升级） */
  appliedMigrations: string[];
  /** 本次启动产生的自动备份文件名 */
  backupName: string | null;
  close: () => void;
}

/** 迁移失败时抛出，携带备份路径供调用方展示。 */
export class MigrationError extends Error {
  constructor(
    message: string,
    readonly backupName: string | null,
    readonly failedTag: string,
  ) {
    super(message);
    this.name = "MigrationError";
  }
}

/**
 * 打开（并在需要时创建）SQLite 数据库，随后按版本执行迁移。
 *
 * ## 版本机制
 *
 * 用 SQLite 内置的 `PRAGMA user_version` 记录 schema 版本，
 * 版本号 = 已应用迁移的数量。它存在文件头里，读写零开销，
 * 也不需要额外建表。
 *
 * ## 为什么必须有版本号
 *
 * 旧实现是「每次启动把所有迁移 SQL 全跑一遍」。
 * 只要有一条迁移用了 ALTER TABLE，第二次启动就会报
 * duplicate column name 而直接崩溃 —— 因为 ALTER 不是幂等的
 * （SQLite 没有 ADD COLUMN IF NOT EXISTS）。
 *
 * ## 三条保证
 *
 * - **单个迁移一个事务**：失败回滚，不会留下半截表结构
 * - **升级前自动备份**：备份永久保留，出问题可手工恢复
 * - **降级拒绝启动**：库版本高于程序时明确报错，而不是带着未知结构运行
 */
export function createNodeDatabase(filePath: string, options?: { readonly?: boolean }): NodeDatabase {
  const readonly = options?.readonly ?? false;

  if (filePath !== ":memory:") {
    mkdirSync(dirname(filePath), { recursive: true });
  }

  const raw = new Database(filePath, { readonly });
  raw.pragma("journal_mode = WAL");
  raw.pragma("busy_timeout = 5000");
  raw.pragma("foreign_keys = ON");

  const applied = raw.pragma("user_version", { simple: true }) as number;

  /*
   * 2.0.0 是第一个使用版本号的版本，它之前的库 user_version 都是 0，
   * 但表其实已经建好了。判断依据：user_version 为 0 且 users 表已存在，
   * 说明这是一个 2.0.0 时期创建的库，直接标记为「0 和 1 号迁移已完成」。
   *
   * 因为项目明确不支持从 2.0.0 之前的版本升级，这里不需要
   * 更复杂的兼容分支。
   */
  const hasExistingSchema =
    applied === 0 &&
    raw
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
      .get() !== undefined;

  const startingVersion = hasExistingSchema ? Math.min(2, SCHEMA_VERSION) : applied;

  if (hasExistingSchema) {
    raw.pragma(`user_version = ${startingVersion}`);
  }

  const wrapped = () => {
    const db = drizzle(raw, { schema }) as unknown as AppDatabase;
    return { db, raw, close: () => raw.close() };
  };

  // 降级保护：库比程序新
  if (startingVersion > SCHEMA_VERSION) {
    raw.close();
    throw new Error(
      `数据库版本为 ${startingVersion}，高于当前程序支持的 ${SCHEMA_VERSION}。\n` +
        `这通常是安装了旧版本导致的。请安装更新的版本，\n` +
        `或从 data 目录下的 .bak 备份文件恢复后重试。`,
    );
  }

  // 无需迁移
  if (startingVersion === SCHEMA_VERSION) {
    return { ...wrapped(), appliedMigrations: [], backupName: null };
  }

  // 只读连接不能迁移
  if (readonly) {
    raw.close();
    throw new Error(
      `数据库需要从版本 ${startingVersion} 升级到 ${SCHEMA_VERSION}，但连接是只读的。`,
    );
  }

  /*
   * 升级前备份（永久保留，不自动删除）。
   *
   * 内存库（:memory:）没有文件可复制，跳过备份 ——
   * 它本来就不承载持久数据，丢了也无所谓。
   */
  const isMemory = filePath === ":memory:";
  let backupName: string | null = null;
  if (!isMemory) {
    try {
      backupName = createBackup(filePath, startingVersion, "migration").name;
    } catch (error) {
      raw.close();
      throw new Error(`升级前备份失败，已中止升级：${error}`);
    }
  }

  const pending = migrations.filter((m) => m.idx >= startingVersion);
  const appliedTags: string[] = [];

  for (const migration of pending) {
    raw.exec("BEGIN");
    try {
      raw.exec(migration.sql);
      // 版本号与 DDL 在同一个事务里提交，不会出现「表改了但版本没记」
      raw.pragma(`user_version = ${migration.idx + 1}`);
      raw.exec("COMMIT");
      appliedTags.push(migration.tag);
    } catch (error) {
      try {
        raw.exec("ROLLBACK");
      } catch {
        /* 回滚本身失败时保留原始错误 */
      }
      raw.close();
      throw new MigrationError(
        `数据库升级到 ${migration.tag} 失败：${error}\n` +
          `原数据已备份到 ${backupName}。把它重命名为 ${filePath.split(/[\\/]/).pop()} ` +
          `即可回到升级前的状态。`,
        backupName,
        migration.tag,
      );
    }
  }

  return { ...wrapped(), appliedMigrations: appliedTags, backupName };
}