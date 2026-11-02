import { describe, expect, it, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, existsSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import Database from "better-sqlite3";

import {
  backupExists,
  createBackup,
  deleteBackup,
  listBackups,
  restoreBackup,
} from "../src/backup.js";
import { createNodeDatabase } from "../src/adapters/node.js";
import { SCHEMA_VERSION } from "../src/migrations.js";

let dir: string;
let dbPath: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "toolbox-backup-"));
  dbPath = join(dir, "local.db");
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

/** 建一个最小的 SQLite 库，写一条可辨识的数据。 */
function makeDb(marker: string) {
  const raw = new Database(dbPath);
  raw.exec("CREATE TABLE IF NOT EXISTS probe (id text PRIMARY KEY, value text);");
  raw.prepare("INSERT OR REPLACE INTO probe (id, value) VALUES ('k', ?)").run(marker);
  raw.pragma(`user_version = ${SCHEMA_VERSION}`);
  raw.close();
}

function readMarker(): string | null {
  const raw = new Database(dbPath, { readonly: true });
  try {
    const row = raw.prepare("SELECT value FROM probe WHERE id='k'").get() as
      | { value: string }
      | undefined;
    return row?.value ?? null;
  } finally {
    raw.close();
  }
}

describe("备份创建", () => {
  it("生成符合命名的文件，且能读回", () => {
    makeDb("v1");
    const file = createBackup(dbPath, SCHEMA_VERSION, "migration");

    expect(file.name).toMatch(/^local\.db\.v\d+-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.bak$/);
    expect(existsSync(file.path)).toBe(true);
    expect(file.size).toBeGreaterThan(0);
    expect(file.version).toBe(SCHEMA_VERSION);
    expect(backupExists(dbPath, file.name)).toBe(true);
  });

  it("备份内容与源库一致", () => {
    makeDb("keep-me");
    const file = createBackup(dbPath, SCHEMA_VERSION, "manual");

    const backupDb = new Database(file.path, { readonly: true });
    try {
      const row = backupDb.prepare("SELECT value FROM probe WHERE id='k'").get() as {
        value: string;
      };
      expect(row.value).toBe("keep-me");
    } finally {
      backupDb.close();
    }
  });
});

describe("备份列表", () => {
  it("按时间倒序，最新在前", async () => {
    makeDb("x");
    const a = createBackup(dbPath, SCHEMA_VERSION, "manual");
    // 文件名时间戳精确到秒，两次备份需要错开
    await new Promise((r) => setTimeout(r, 1100));
    const b = createBackup(dbPath, SCHEMA_VERSION, "manual");

    const list = listBackups(dbPath);
    expect(list).toHaveLength(2);
    expect(list[0]!.name).toBe(b.name);
    expect(list[1]!.name).toBe(a.name);
  });

  it("不会把其它库的备份算进来", () => {
    makeDb("x");
    createBackup(dbPath, SCHEMA_VERSION, "manual");
    // 另一个库的同目录备份
    writeFileSync(join(dir, "other.db.v2-2026-01-01T00-00-00.bak"), "not ours");

    const list = listBackups(dbPath);
    expect(list).toHaveLength(1);
  });

  it("目录不存在时返回空数组", () => {
    expect(listBackups(join(dir, "nope", "x.db"))).toEqual([]);
  });
});

describe("备份删除", () => {
  it("删除指定备份，其余保留", () => {
    makeDb("x");
    const a = createBackup(dbPath, SCHEMA_VERSION, "manual");
    const b = createBackup(dbPath, SCHEMA_VERSION, "manual");

    deleteBackup(dbPath, a.name);

    expect(existsSync(a.path)).toBe(false);
    expect(existsSync(b.path)).toBe(true);
    expect(listBackups(dbPath)).toHaveLength(1);
  });

  it("拒绝非法文件名（路径穿越）", () => {
    makeDb("x");
    expect(() => deleteBackup(dbPath, "../../etc/passwd")).toThrow("不合法");
  });

  it("文件不存在时报错", () => {
    makeDb("x");
    expect(() => deleteBackup(dbPath, "local.db.v2-2020-01-01T00-00-00.bak")).toThrow("不存在");
  });
});

describe("备份恢复", () => {
  it("恢复后数据回到备份时的状态", () => {
    makeDb("original");
    const file = createBackup(dbPath, SCHEMA_VERSION, "manual");

    // 改掉数据
    const raw = new Database(dbPath);
    raw.prepare("UPDATE probe SET value='changed' WHERE id='k'").run();
    raw.close();
    expect(readMarker()).toBe("changed");

    // 恢复
    restoreBackup(dbPath, file.name, SCHEMA_VERSION);

    expect(readMarker()).toBe("original");
  });

  it("恢复前会为当前数据生成安全副本", () => {
    makeDb("before");
    const file = createBackup(dbPath, SCHEMA_VERSION, "manual");
    const countBefore = listBackups(dbPath).length;

    const { safetyCopy } = restoreBackup(dbPath, file.name, SCHEMA_VERSION);

    expect(safetyCopy).toMatch(/\.bak$/);
    expect(listBackups(dbPath)).toHaveLength(countBefore + 1);
    expect(backupExists(dbPath, safetyCopy)).toBe(true);
  });

  it("拒绝非 SQLite 文件", () => {
    makeDb("x");
    const fake = "local.db.v2-2026-01-01T00-00-00.bak";
    writeFileSync(join(dir, fake), "this is not a database");

    expect(() => restoreBackup(dbPath, fake, SCHEMA_VERSION)).toThrow("不是有效的数据库备份");
  });

  it("拒绝路径穿越", () => {
    makeDb("x");
    expect(() => restoreBackup(dbPath, "../evil.bak", SCHEMA_VERSION)).toThrow("不合法");
  });
});

describe("schema 版本机制", () => {
  it("新库建好后版本号等于 SCHEMA_VERSION", () => {
    const created = createNodeDatabase(dbPath);
    created.close();

    const raw = new Database(dbPath, { readonly: true });
    expect(raw.pragma("user_version", { simple: true })).toBe(SCHEMA_VERSION);
    raw.close();
  });

  it("重复打开不会重复迁移，也不产生备份", () => {
    createNodeDatabase(dbPath).close();
    const before = readdirSync(dir).filter((f) => f.endsWith(".bak")).length;

    const second = createNodeDatabase(dbPath);
    expect(second.appliedMigrations).toEqual([]);
    expect(second.backupName).toBeNull();
    second.close();

    const after = readdirSync(dir).filter((f) => f.endsWith(".bak")).length;
    expect(after).toBe(before);
  });

  it("降级安装时拒绝启动并给出提示", () => {
    createNodeDatabase(dbPath).close();

    // 手工把版本号推到未来
    const raw = new Database(dbPath);
    raw.pragma(`user_version = ${SCHEMA_VERSION + 1}`);
    raw.close();

    expect(() => createNodeDatabase(dbPath)).toThrow(/高于当前程序支持/);
  });

  it("2.0.0 时期的老库（user_version=0 但表已存在）能正确识别", () => {
    // 模拟 2.0.0 发布的库：表齐全但没写版本号
    const raw = new Database(dbPath);
    raw.exec("CREATE TABLE IF NOT EXISTS users (id text PRIMARY KEY, username text);");
    raw.close();

    const opened = createNodeDatabase(dbPath);
    // 应被识别为已完成的迁移，不再执行
    expect(opened.appliedMigrations).toEqual([]);
    opened.close();

    const check = new Database(dbPath, { readonly: true });
    expect(check.pragma("user_version", { simple: true })).toBe(SCHEMA_VERSION);
    check.close();
  });

  it("内存库也能正常建表", () => {
    const mem = createNodeDatabase(":memory:");
    expect(mem.appliedMigrations.length).toBeGreaterThan(0);
    mem.close();
  });
});
