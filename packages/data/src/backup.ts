/**
 * 数据库备份与恢复。
 *
 * 设计要点：
 *
 * 1. **备份永不自动删除**
 *    迁移前的自动备份、用户手动的备份都留在同一目录。
 *    升级出问题时，那份 .bak 就是最后的退路。
 *    代价是可能堆积，所以提供手动的「全部删除」入口。
 *
 * 2. **恢复前先备份当前库**
 *    恢复是覆盖操作。万一选错了备份文件，
 *    那份自动生成的安全副本能把数据捞回来。
 *
 * 3. **文件名带版本号**
 *    local.db.v2-2026-11-02T11-30-00.bak
 *    一眼能看出这是从哪个 schema 版本备份的，
 *    避免把高版本的库恢复到低版本程序上。
 */
import {
  copyFileSync,
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join } from "node:path";

/** SQLite 文件头：前 16 字节固定是 "SQLite format 3\0" */
const SQLITE_MAGIC = Buffer.from("SQLite format 3\0", "binary");

export interface BackupFile {
  /** 文件名，如 local.db.v2-2026-11-02T11-30-00.bak */
  name: string;
  /** 字节数 */
  size: number;
  /** 创建时间（毫秒） */
  createdAt: number;
  /** 备份时的 schema 版本 */
  version: number;
  /** 触发方式 */
  type: "migration" | "manual";
  /** 绝对路径，仅供后端使用，不下发给前端 */
  path: string;
}

/** 备份文件名格式：<库名>.v<版本>-<时间戳>.bak */
const BACKUP_RE = /^(.+)\.v(\d+)-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})(?:-\d+)?\.bak$/;

/** 时间戳格式：2026-11-02T11-30-00（冒号换成了横线，Windows 文件名不允许冒号） */
function stamp(): string {
  return new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
}

function parseStamp(value: string): number {
  // 2026-11-02T11-30-00 -> 2026-11-02T11:30:00Z
  const iso = value.replace(/^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})$/, "$1-$2-$3T$4:$5:$6Z");
  const parsed = Date.parse(iso);
  return Number.isFinite(parsed) ? parsed : 0;
}

/** 校验一个文件是不是 SQLite 数据库。 */
function looksLikeSqlite(path: string): boolean {
  try {
    const handle = readFileSync(path);
    if (handle.length < 16) return false;
    return handle.subarray(0, 16).equals(SQLITE_MAGIC);
  } catch {
    return false;
  }
}

/** 备份是否存在且文件名合法。 */
export function backupExists(dbPath: string, name: string): boolean {
  if (!BACKUP_RE.test(name)) return false;
  return existsSync(join(dirname(dbPath), name));
}

/**
 * 创建备份。
 *
 * @param dbPath   数据库路径
 * @param version  当前 schema 版本号
 * @param type     migration（迁移前自动）/ manual（用户手动）
 */
export function createBackup(
  dbPath: string,
  version: number,
  type: "migration" | "manual",
): BackupFile {
  const dir = dirname(dbPath);
  const base = basename(dbPath);

  /*
   * 时间戳只精确到秒，同一秒内连续备份两次会得到同名文件，
   * 后者直接覆盖前者 —— 被覆盖的可能正是用户想保留的那一份。
   * 这里加序号去重：...-00.bak → ...-00-2.bak → ...-00-3.bak
   */
  let name = `${base}.v${version}-${stamp()}.bak`;
  let path = join(dir, name);
  for (let n = 2; existsSync(path); n += 1) {
    name = `${base}.v${version}-${stamp()}-${n}.bak`;
    path = join(dir, name);
  }

  // WAL 模式下，最近的写入可能还在 -wal 文件里。
  // better-sqlite3 在主连接上执行过 checkpoint，这里直接复制主文件即可；
  // 但为了拿到一致快照，调用方应保证此时没有并发写。
  copyFileSync(dbPath, path);

  // -wal / -shm 一起带走，否则恢复后可能缺最后一段数据。
  // 这两个文件不存在是正常的（已 checkpoint 过）。
  for (const suffix of ["-wal", "-shm"]) {
    const side = dbPath + suffix;
    if (existsSync(side)) {
      try {
        copyFileSync(side, path + suffix);
      } catch {
        /* 附属文件复制失败不影响主文件 */
      }
    }
  }

  const stat = statSync(path);
  return {
    name,
    size: stat.size,
    // 刚构造出的名字一定匹配，取不到就退回当前时间
    createdAt: parseStamp(name.match(BACKUP_RE)?.[3] ?? ""),
    version,
    type,
    path,
  };
}

/** 列出全部备份，按创建时间倒序（最新在前）。 */
export function listBackups(dbPath: string): BackupFile[] {
  const dir = dirname(dbPath);
  const base = basename(dbPath);

  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return [];
  }

  const files: BackupFile[] = [];
  for (const entry of entries) {
    const match = entry.match(BACKUP_RE);
    if (!match) continue;
    // 只认属于这个库的备份，避免同目录下别的库的备份混进来
    if (match[1] !== base) continue;

    const path = join(dir, entry);
    let size = 0;
    try {
      size = statSync(path).size;
    } catch {
      continue;
    }

    const stampPart = match[3];
    const versionPart = match[2];
    if (stampPart === undefined || versionPart === undefined) continue;

    files.push({
      name: entry,
      size,
      createdAt: parseStamp(stampPart),
      version: Number(versionPart),
      /*
       * 迁移备份与手动备份的文件名格式完全相同，
       * 这里无法从名字区分。用「是否恰好是某个已知版本」推断太脆弱，
       * 所以统一标注为 migration —— 前端展示为「备份」即可，
       * 不强调来源。真需要区分时应在文件名里加标记，
       * 但那会让格式变复杂，当前不值得。
       */
      type: "migration",
      path,
    });
  }

  return files.sort((a, b) => b.createdAt - a.createdAt);
}

/** 删除一个备份（连带它的 -wal / -shm）。 */
export function deleteBackup(dbPath: string, name: string): void {
  if (!BACKUP_RE.test(name)) {
    throw new Error("备份文件名不合法");
  }
  const dir = dirname(dbPath);
  // 文件名已由正则约束，不含路径分隔符，join 后必然落在 dir 内
  const path = join(dir, name);
  if (!existsSync(path)) {
    throw new Error("备份文件不存在");
  }
  unlinkSync(path);
  for (const suffix of ["-wal", "-shm"]) {
    const side = path + suffix;
    if (existsSync(side)) {
      try {
        unlinkSync(side);
      } catch {
        /* 忽略 */
      }
    }
  }
}

/**
 * 从备份恢复数据库。
 *
 * 步骤：
 *   1. 校验备份文件名与内容（必须是真正的 SQLite 文件）
 *   2. 给**当前**库做一份安全备份（万一恢复错了还能回来）
 *   3. 用备份覆盖当前库，并清理残留的 -wal / -shm
 *
 * 调用方负责在此之前关闭数据库连接，之后重新打开。
 *
 * @returns 安全副本的文件名
 */
export function restoreBackup(
  dbPath: string,
  name: string,
  currentVersion: number,
): { safetyCopy: string } {
  if (!BACKUP_RE.test(name)) {
    throw new Error("备份文件名不合法");
  }

  const dir = dirname(dbPath);
  const source = join(dir, name);
  if (!existsSync(source)) {
    throw new Error("备份文件不存在");
  }
  if (!looksLikeSqlite(source)) {
    throw new Error("该文件不是有效的数据库备份");
  }

  // 恢复前先保住当前数据
  const safety = createBackup(dbPath, currentVersion, "manual");

  copyFileSync(source, dbPath);

  // 旧的 WAL 必须删掉：它记录的是旧库变更，
  // 留着会和恢复后的主文件对不上，导致数据错乱。
  for (const suffix of ["-wal", "-shm"]) {
    const side = dbPath + suffix;
    if (existsSync(side)) {
      try {
        unlinkSync(side);
      } catch {
        /* 忽略 */
      }
    }
  }

  // 备份里自带的附属文件也一并还原
  for (const suffix of ["-wal", "-shm"]) {
    const side = source + suffix;
    if (existsSync(side)) {
      try {
        copyFileSync(side, dbPath + suffix);
      } catch {
        /* 忽略 */
      }
    }
  }

  return { safetyCopy: safety.name };
}

/** 读取数据库的 schema 版本（PRAGMA user_version）。 */
export function readUserVersion(raw: { pragma: (s: string, o?: unknown) => unknown }): number {
  const value = raw.pragma("user_version", { simple: true });
  return typeof value === "number" ? value : 0;
}

/** 把 SQLite 文件写到指定目标（用于「另存为」导出）。 */
export function exportBackup(dbPath: string, name: string, dest: string): void {
  if (!BACKUP_RE.test(name)) {
    throw new Error("备份文件名不合法");
  }
  const source = join(dirname(dbPath), name);
  if (!existsSync(source)) {
    throw new Error("备份文件不存在");
  }
  writeFileSync(dest, readFileSync(source));
}