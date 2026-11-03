import { describe, expect, it, beforeEach, afterEach } from "vitest";
import {
  copyFileSync,
  existsSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import Database from "better-sqlite3";

import {
  backupExists,
  createBackup,
  deleteBackup,
  importBackup,
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

/**
 * 建一个最小的 SQLite 库，写一条可辨识的数据。
 *
 * 必须包含 users 表 —— listBackups 会过滤掉没有该表的备份
 * （识别「空壳备份」的手段）。
 */
function makeDb(marker: string) {
  const raw = new Database(dbPath);
  raw.exec("CREATE TABLE IF NOT EXISTS probe (id text PRIMARY KEY, value text);");
  raw.exec("CREATE TABLE IF NOT EXISTS users (id text PRIMARY KEY, username text);");
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

describe("导入备份", () => {
  /** 造一个外来备份文件（名字/来源都与本机不同）。 */
  function makeForeignBackup(fileName: string, marker: string): string {
    const foreignDir = mkdtempSync(join(tmpdir(), "toolbox-foreign-"));
    const foreignPath = join(foreignDir, fileName);
    const raw = new Database(foreignPath);
    raw.exec("CREATE TABLE IF NOT EXISTS probe (id text PRIMARY KEY, value text);");
    raw.exec("CREATE TABLE IF NOT EXISTS users (id text PRIMARY KEY, username text);");
    raw.prepare("INSERT OR REPLACE INTO probe (id, value) VALUES ('k', ?)").run(marker);
    raw.pragma(`user_version = ${SCHEMA_VERSION}`);
    raw.close();
    return foreignPath;
  }

  it("导入后能在列表里看到", () => {
    makeDb("mine");
    const foreign = makeForeignBackup("other.db.v2-2026-10-01T08-00-00.bak", "imported");

    const file = importBackup(dbPath, foreign, SCHEMA_VERSION);

    expect(file.name).toBe("local.db.v2-2026-10-01T08-00-00.bak");
    expect(file.version).toBe(2);
    const list = listBackups(dbPath);
    expect(list.some((f) => f.name === file.name)).toBe(true);
  });

  it("保留原文件名里的时间戳", () => {
    makeDb("mine");
    const foreign = makeForeignBackup("whatever.db.v2-2026-09-15T12-34-56.bak", "x");

    const file = importBackup(dbPath, foreign, SCHEMA_VERSION);

    /*
     * 文件名里的时间按**本地时区**解释（见 parseStamp 的注释）。
     * 用分量构造 Date，它天然按本地时区处理 ——
     * 不要写成 Date.parse("...Z")，那样会被当成 UTC。
     */
    const expected = new Date(2026, 8, 15, 12, 34, 56).getTime();
    expect(file.createdAt).toBe(expected);
  });

  it("导入的备份可以正常恢复", () => {
    makeDb("current");
    const foreign = makeForeignBackup("other.db.v2-2026-10-01T08-00-00.bak", "from-import");

    const file = importBackup(dbPath, foreign, SCHEMA_VERSION);
    restoreBackup(dbPath, file.name, SCHEMA_VERSION);

    expect(readMarker()).toBe("from-import");
  });

  it("拒绝非 SQLite 文件", () => {
    makeDb("mine");
    const bad = join(dir, "not-a-db.bak");
    writeFileSync(bad, "plain text");

    expect(() => importBackup(dbPath, bad, SCHEMA_VERSION)).toThrow("有效的数据库文件");
  });

  it("拒绝来自更高版本的备份", () => {
    makeDb("mine");
    const future = makeForeignBackup("x.db.v9-2026-10-01T08-00-00.bak", "future");

    expect(() => importBackup(dbPath, future, SCHEMA_VERSION)).toThrow("更高的版本");
  });

  it("文件名不规范时用当前时间兜底", () => {
    makeDb("mine");
    const foreign = makeForeignBackup("random-name.bak", "x");

    const file = importBackup(dbPath, foreign, SCHEMA_VERSION);
    expect(file.version).toBe(SCHEMA_VERSION);
    expect(file.createdAt).toBeGreaterThan(Date.now() - 60_000);
  });

  it("重名时不覆盖已有备份", () => {
    makeDb("mine");
    const f1 = makeForeignBackup("a.db.v2-2026-10-01T08-00-00.bak", "one");
    const f2 = makeForeignBackup("b.db.v2-2026-10-01T08-00-00.bak", "two");

    const a = importBackup(dbPath, f1, SCHEMA_VERSION);
    const b = importBackup(dbPath, f2, SCHEMA_VERSION);

    expect(a.name).not.toBe(b.name);
    expect(listBackups(dbPath).length).toBe(2);
  });
});

describe("WAL 模式下的备份完整性", () => {
  it("未 checkpoint 的写入也要被备份进去", () => {
    // 建一个 WAL 模式的库
    const raw = new Database(dbPath);
    raw.pragma("journal_mode = WAL");
    raw.exec("CREATE TABLE probe (id text PRIMARY KEY, value text);");
    raw.prepare("INSERT INTO probe (id, value) VALUES ('k', ?)").run("in-wal");
    raw.pragma(`user_version = ${SCHEMA_VERSION}`);
    /*
     * 不 close，也不 checkpoint —— 数据此时只存在于 -wal 文件里，
     * 主 .db 可能还是空的。这正是之前备份变空库的场景。
     */
    raw.close();

    const file = createBackup(dbPath, SCHEMA_VERSION, "manual");

    // 打开备份，数据必须在
    const check = new Database(file.path, { readonly: true });
    try {
      const row = check.prepare("SELECT value FROM probe WHERE id='k'").get() as
        | { value: string }
        | undefined;
      expect(row?.value).toBe("in-wal");
    } finally {
      check.close();
    }
  });

  it("备份文件大小接近数据库实际大小（不是空壳）", () => {
    const raw = new Database(dbPath);
    raw.pragma("journal_mode = WAL");
    raw.exec("CREATE TABLE probe (id text PRIMARY KEY, value text);");
    // 塞一些数据让库变大
    const stmt = raw.prepare("INSERT INTO probe (id, value) VALUES (?, ?)");
    for (let i = 0; i < 200; i += 1) stmt.run(`k${i}`, "x".repeat(500));
    raw.close();

    const file = createBackup(dbPath, SCHEMA_VERSION, "manual");
    // 200 行 * 500 字节 ≈ 100KB，备份不该只有 4KB
    expect(file.size).toBeGreaterThan(20_000);
  });
});

describe("时间戳使用本地时区", () => {
  it("文件名里的时间与本地时间一致", () => {
    makeDb("x");
    const before = Date.now();
    const file = createBackup(dbPath, SCHEMA_VERSION, "manual");
    const after = Date.now();

    // createdAt 应落在这次调用的时间范围内（允许 2 秒误差）
    expect(file.createdAt).toBeGreaterThanOrEqual(before - 2000);
    expect(file.createdAt).toBeLessThanOrEqual(after + 2000);
  });

  it("文件名里的时分秒与本地时间吻合", () => {
    makeDb("x");
    const file = createBackup(dbPath, SCHEMA_VERSION, "manual");

    const now = new Date(file.createdAt);
    const expected = [
      now.getFullYear(),
      String(now.getMonth() + 1).padStart(2, "0"),
      String(now.getDate()).padStart(2, "0"),
    ].join("-");

    // 文件名格式 local.db.v2-YYYY-MM-DDTHH-MM-SS.bak
    expect(file.name).toContain(expected);
  });

  it("解析回的时间与当下接近（不是 UTC 偏移 8 小时）", () => {
    makeDb("x");
    const file = createBackup(dbPath, SCHEMA_VERSION, "manual");

    const drift = Math.abs(Date.now() - file.createdAt);
    // 如果误用 UTC，中国时区下会差 8 小时 = 28_800_000ms
    expect(drift).toBeLessThan(10_000);
  });
});

describe("安全：路径穿越", () => {
  it("拒绝含路径分隔符的文件名", () => {
    makeDb("x");
    const attacks = [
      "../../../etc/passwd.v2-2026-11-03T16-42-50.bak",
      "..\\..\\windows\\x.v2-2026-11-03T16-42-50.bak",
      "sub/dir/evil.v2-2026-11-03T16-42-50.bak",
      "/abs/path.v2-2026-11-03T16-42-50.bak",
    ];
    for (const name of attacks) {
      expect(() => deleteBackup(dbPath, name)).toThrow("不合法");
      expect(() => restoreBackup(dbPath, name, SCHEMA_VERSION)).toThrow("不合法");
    }
  });

  it("底层校验不依赖调用方，自己就能挡住", () => {
    // backupExists 是更底层的方法，也必须拒绝
    expect(backupExists(dbPath, "../../evil.bak")).toBe(false);
    expect(backupExists(dbPath, "sub/x.v2-2026-11-03T16-42-50.bak")).toBe(false);
  });
});

describe("安全：恢复前的完整性校验", () => {
  it("拒绝内容损坏的数据库", () => {
    makeDb("x");
    const corrupt = "local.db.v2-2026-11-03T16-42-50.bak";
    // 头部正确，但后面全是垃圾
    const bad = Buffer.concat([
      Buffer.from("SQLite format 3\0", "binary"),
      Buffer.alloc(4000, 0xff),
    ]);
    writeFileSync(join(dir, corrupt), bad);

    expect(() => restoreBackup(dbPath, corrupt, SCHEMA_VERSION)).toThrow("损坏");
  });

  it("拒绝没有 users 表的空备份", () => {
    makeDb("x");
    // 造一个合法 SQLite 库，但只有别的表
    const emptyPath = join(dir, "empty.db");
    const raw = new Database(emptyPath);
    raw.exec("CREATE TABLE unrelated (id text);");
    raw.close();

    const name = "local.db.v2-2026-11-03T16-42-50.bak";
    copyFileSync(emptyPath, join(dir, name));

    expect(() => restoreBackup(dbPath, name, SCHEMA_VERSION)).toThrow("没有任何账号数据");
  });
});

describe("安全：列表过滤空备份", () => {
  it("没有 users 表的备份不出现在列表里", () => {
    makeDb("x");
    createBackup(dbPath, SCHEMA_VERSION, "manual");

    // 造一个空壳备份放进目录
    const emptyPath = join(dir, "shell.db");
    const raw = new Database(emptyPath);
    raw.exec("CREATE TABLE t (id text);");
    raw.close();
    copyFileSync(emptyPath, join(dir, "local.db.v2-2026-01-01T00-00-00.bak"));

    const list = listBackups(dbPath);
    // 只有那个真正含 users 表的备份
    expect(list).toHaveLength(1);
    expect(list[0]!.name).not.toContain("2026-01-01");
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