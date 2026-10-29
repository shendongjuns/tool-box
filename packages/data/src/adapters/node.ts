import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { migrations } from "../migrations.js";
import * as schema from "../schema.js";
import type { AppDatabase } from "../types.js";

export interface NodeDatabase {
  db: AppDatabase;
  raw: Database.Database;
  close: () => void;
}

/**
 * 打开（并在需要时创建）SQLite 数据库，随后执行幂等迁移。
 *
 * - WAL 提升并发读性能；busy_timeout 避免瞬时锁直接抛错；
 * - 迁移按 idx 顺序执行，全部是 IF NOT EXISTS，可安全重复执行。
 */
export function createNodeDatabase(filePath: string, options?: { readonly?: boolean }): NodeDatabase {
  if (filePath !== ":memory:") {
    mkdirSync(dirname(filePath), { recursive: true });
  }
  const raw = new Database(filePath, { readonly: options?.readonly ?? false });
  raw.pragma("journal_mode = WAL");
  raw.pragma("busy_timeout = 5000");
  raw.pragma("foreign_keys = ON");

  for (const migration of migrations) {
    raw.exec(migration.sql);
  }

  const db = drizzle(raw, { schema }) as unknown as AppDatabase;
  return { db, raw, close: () => raw.close() };
}
