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
import SqliteDatabase from "better-sqlite3";
import {
  copyFileSync,
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
  unlinkSync,
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
/**
 * 文件名里的时间戳用**本地时间**。
 *
 * 之前用 toISOString()（UTC），结果在中国时区下，
 * 14:43 备份的文件叫 ...T06-43-...，用户完全对不上号。
 *
 * 备份文件是给人看的，就该用人的时区。
 * 跨时区迁移时可能产生歧义，但那种场景远比日常使用罕见，
 * 而且恢复时并不依赖这个时间戳（只是排序与展示用）。
 */
function stamp(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return (
    `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}` +
    `T${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}`
  );
}

/**
 * 把文件名里的时间戳解析成毫秒。
 *
 * 按**本地时间**解析，与 stamp() 的生成方式对应。
 * 用 Date 构造函数的分量形式（年月日时分秒），
 * 它天然按本地时区解释 —— 不要拼成 ISO 字符串再 parse，
 * 那样会被当成 UTC。
 */
function parseStamp(value: string): number {
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})$/);
  if (!match) return 0;
  const [, y, mo, d, h, mi, s] = match;
  const parsed = new Date(
    Number(y),
    Number(mo) - 1,
    Number(d),
    Number(h),
    Number(mi),
    Number(s),
  ).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
}

/**
 * 把 WAL 内容合并回主数据库文件。
 *
 * 用独立的只读连接执行 —— 不干扰主进程的连接池。
 * PRAGMA wal_checkpoint(TRUNCATE) 会等待所有读事务结束后
 * 把 WAL 写回主文件，然后把 -wal 截断为空。
 *
 * 失败不抛错：极端情况下（比如有长事务挂着）checkpoint 可能
 * 拿不到排他锁，此时回退到「连 -wal 一起复制」的策略。
 */
function checkpointSqlite(dbPath: string): void {
  try {
    const conn = new SqliteDatabase(dbPath);
    try {
      conn.pragma("wal_checkpoint(TRUNCATE)");
    } finally {
      conn.close();
    }
  } catch {
    /* 打不开就跳过，交给后面的 -wal 复制兜底 */
  }
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

  /*
   * 关键：先做 WAL checkpoint。
   *
   * SQLite 的 WAL 模式下，最近的写入先落在 -wal 文件里，
   * 主 .db 文件可能仍是几 KB 的空壳。
   *
   * 如果直接复制主文件，备份就是个空库 —— 恢复后数据全丢。
   * 这个坑极隐蔽：文件存在、大小正常、能打开，只是没有数据。
   *
   * 用 TRUNCATE 模式把 WAL 全部合并回主文件并清空 -wal，
   * 这样复制出来的才是完整快照。
   */
  checkpointSqlite(dbPath);

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
 * 导入外部备份文件。
 *
 * 场景：用户从另一台机器（或另一个部署）下载了备份，
 * 想把它放进本地的备份列表，之后可以像普通备份一样恢复。
 *
 * 三个关键处理：
 *
 * 1. **文件名要重写**
 *    外来的文件名可能是 local.db.v2-...，而本机库叫 toolbox.db。
 *    直接放进目录会被 listBackups 的前缀过滤掉，看不见。
 *    所以按本机库名重新生成文件名，保留原有的版本号与时间戳。
 *
 * 2. **内容要校验**
 *    只接受真正的 SQLite 文件，避免把任意文件塞进备份目录。
 *
 * 3. **版本要检查**
 *    备份的 schema 版本不能高于当前程序支持的上限，
 *    否则恢复后会是一个程序读不懂的库。
 */
export function importBackup(
  dbPath: string,
  sourcePath: string,
  currentVersion: number,
): BackupFile {
  if (!existsSync(sourcePath)) {
    throw new Error("文件不存在");
  }
  if (!looksLikeSqlite(sourcePath)) {
    throw new Error("这不是有效的数据库文件");
  }

  const dir = dirname(dbPath);
  const base = basename(dbPath);

  /*
   * 尝试从原文件名提取版本与时间戳。
   * 提取失败（比如用户手动改过名）就用当前版本和当前时间。
   */
  const original = basename(sourcePath);
  const match = original.match(BACKUP_RE);
  const version = match?.[2] ? Number(match[2]) : currentVersion;
  const stampPart = match?.[3] ?? stamp();

  if (version > currentVersion) {
    throw new Error(
      `这份备份来自更高的版本 v${version}，当前程序只支持到 v${currentVersion}。请升级后再导入。`,
    );
  }

  // 用本机库名重写文件名，保留原版本号与时间戳
  let name = `${base}.v${version}-${stampPart}.bak`;
  let path = join(dir, name);
  for (let n = 2; existsSync(path); n += 1) {
    name = `${base}.v${version}-${stampPart}-${n}.bak`;
    path = join(dir, name);
  }

  copyFileSync(sourcePath, path);

  const stat = statSync(path);
  return {
    name,
    size: stat.size,
    createdAt: parseStamp(stampPart),
    version,
    type: "manual",
    path,
  };
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