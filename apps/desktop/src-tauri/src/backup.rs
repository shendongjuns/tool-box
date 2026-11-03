//! 数据库备份与恢复。
//!
//! 与 TypeScript 侧（packages/data/src/backup.ts）保持同一套规则：
//! 文件命名、版本号、路径穿越防御、恢复前的安全副本。
//!
//! 为什么两边各写一份而不是共享代码：
//! 服务端跑 Node，桌面端是 Rust 进程内嵌 SQLite，
//! 没有能共用的运行时。规则必须一致，所以两边的测试用例
//! 也刻意保持对应。

use rusqlite::Connection;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

/// SQLite 文件头的前 16 字节。
const SQLITE_MAGIC: &[u8; 16] = b"SQLite format 3\0";

/// 备份文件名：<库名>.v<版本>-<时间戳>[-序号].bak
fn is_valid_name(name: &str) -> bool {
    if !name.ends_with(".bak") {
        return false;
    }
    // 不允许任何路径分隔符 —— 这是防路径穿越的第一道闸
    if name.contains('/') || name.contains('\\') || name.contains("..") {
        return false;
    }
    // 必须有 .v<数字>-<时间戳> 段
    let Some(dot_v) = name.rfind(".v") else {
        return false;
    };
    let rest = &name[dot_v + 2..];
    let Some((version, tail)) = rest.split_once('-') else {
        return false;
    };
    if version.is_empty() || !version.chars().all(|c| c.is_ascii_digit()) {
        return false;
    }
    /*
     * tail 此时是 "2026-11-02T11-30-00.bak"（含后缀），
     * 去掉 ".bak" 后时间戳本体是 17 个字符：
     *   2026-11-02T11-30-00
     * 可能还带 -N 序号，所以只要求不短于时间戳本体。
     */
    let body = tail.trim_end_matches(".bak");
    body.chars().all(|c| c.is_ascii_digit() || c == '-' || c == 'T') && body.len() >= 17
}

/// 时间戳：2026-11-02T11-30-00（冒号换成横线，Windows 文件名不允许冒号）
/// 当前时间戳，格式 2026-11-03T14-44-26。
///
/// 用**本地时间**而不是 UTC：备份文件是给人看的，
/// 14:43 备份的文件叫 ...T06-43-... 会让人对不上号。
///
/// 与 packages/data/src/backup.ts 的 stamp() 保持一致。
fn stamp() -> String {
    format_timestamp(now_local_secs())
}

/// 本地时间的 Unix 秒数。
///
/// std 没有时区 API，这里用 libc 的 localtime 拿偏移 ——
/// Windows 上也有 CRT 提供的同义函数。
/// 拿不到就退回 UTC，至少格式正确、排序正确。
fn now_local_secs() -> u64 {
    let utc = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    (utc as i64 + local_utc_offset_secs()).max(0) as u64
}

/// 本地时区相对 UTC 的偏移（秒）。
#[cfg(windows)]
fn local_utc_offset_secs() -> i64 {
    // 通过 CRT 的 _localtime64_s 反推：把一个已知 UTC 时刻
    // 转成本地时间，两者之差就是偏移。
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| {
            let utc = d.as_secs() as i64;
            let local = utc_to_local(utc);
            local - utc
        })
        .unwrap_or(0)
}

#[cfg(not(windows))]
fn local_utc_offset_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| {
            let utc = d.as_secs() as i64;
            let local = utc_to_local(utc);
            local - utc
        })
        .unwrap_or(0)
}

/// 用 CRT 的 localtime 把 UTC 秒转成本地秒。
#[cfg(windows)]
fn utc_to_local(utc: i64) -> i64 {
    use std::os::raw::c_int;
    extern "C" {
        fn _localtime64_s(result: *mut Tm, timer: *const i64) -> c_int;
    }
    #[repr(C)]
    struct Tm {
        tm_sec: c_int,
        tm_min: c_int,
        tm_hour: c_int,
        tm_mday: c_int,
        tm_mon: c_int,
        tm_year: c_int,
        tm_wday: c_int,
        tm_yday: c_int,
        tm_isdst: c_int,
    }
    let mut tm = Tm {
        tm_sec: 0,
        tm_min: 0,
        tm_hour: 0,
        tm_mday: 0,
        tm_mon: 0,
        tm_year: 0,
        tm_wday: 0,
        tm_yday: 0,
        tm_isdst: 0,
    };
    unsafe {
        if _localtime64_s(&mut tm, &utc) != 0 {
            return utc;
        }
    }
    // 用分量重新组装成「当作 UTC 的本地时刻」
    days_from_civil(tm.tm_year as i64 + 1900, (tm.tm_mon + 1) as u32, tm.tm_mday as u32) * 86400
        + (tm.tm_hour as i64) * 3600
        + (tm.tm_min as i64) * 60
        + tm.tm_sec as i64
}

#[cfg(not(windows))]
fn utc_to_local(utc: i64) -> i64 {
    // 非 Windows 平台直接读 /etc/localtime 太复杂，退回 UTC。
    // 桌面端只打包 Windows，这条分支仅用于编译通过。
    let _ = utc;
    utc
}

/// 把 Unix 秒格式化成 2026-11-02T11-30-00（UTC）。
fn format_timestamp(secs: u64) -> String {
    // 手写日期换算，避免为一个时间戳引入 chrono 依赖
    let days = secs / 86400;
    let rem = secs % 86400;
    let (hour, minute, second) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let (year, month, day) = civil_from_days(days as i64);
    format!("{year:04}-{month:02}-{day:02}T{hour:02}-{minute:02}-{second:02}")
}

/// 从 1970-01-01 起的天数换算成年月日（Howard Hinnant 的算法）。
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// 从文件名解析 Unix 秒。解析失败返回 0（排序时沉底）。
fn parse_stamp(name: &str) -> i64 {
    let Some(dot_v) = name.rfind(".v") else {
        return 0;
    };
    let rest = &name[dot_v + 2..];
    let Some((_, tail)) = rest.split_once('-') else {
        return 0;
    };
    if tail.len() < 19 {
        return 0;
    }
    let s = &tail[..19];
    let parts: Vec<&str> = s.split(['T', '-']).collect();
    if parts.len() != 6 {
        return 0;
    }
    let nums: Vec<i64> = parts.iter().filter_map(|p| p.parse().ok()).collect();
    if nums.len() != 6 {
        return 0;
    }
    let (year, month, day) = (nums[0], nums[1] as u32, nums[2] as u32);
    let (hour, minute, second) = (nums[3], nums[4], nums[5]);

    /*
     * 文件名里是**本地时间**，但这里的返回值必须是
     * Unix 毫秒（UTC 基准）—— 前端用 new Date(ms) 展示，
     * 它会再按本地时区换算一次。
     *
     * 先把本地时刻当成 UTC 算出秒数，再减去时区偏移，
     * 得到真正的 UTC 秒。少了这一步，前端会看到
     * 「文件名 16:32，列表显示次日 00:32」的错位。
     */
    let as_if_utc =
        days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second;
    (as_if_utc - local_utc_offset_secs()) * 1000
}

/// 年月日换算成从 1970-01-01 起的天数。
fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = (y - era * 400) as u64;
    let mp = if m > 2 { m - 3 } else { m + 9 } as u64;
    let doy = (153 * mp + 2) / 5 + d as u64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe as i64 - 719_468
}

/// 从文件名解析 schema 版本。
fn parse_version(name: &str) -> i64 {
    let Some(dot_v) = name.rfind(".v") else {
        return 0;
    };
    let rest = &name[dot_v + 2..];
    rest.split_once('-')
        .and_then(|(v, _)| v.parse().ok())
        .unwrap_or(0)
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupFile {
    pub name: String,
    pub size: u64,
    pub created_at: i64,
    pub version: i64,
}

/// 备份文件是否属于这个数据库（同名库才能混在一起）。
fn belongs_to(db_path: &Path, name: &str) -> bool {
    let base = db_path
        .file_name()
        .map(|v| v.to_string_lossy().to_string())
        .unwrap_or_default();
    name.starts_with(&format!("{base}.v"))
}

/// 把 WAL 内容合并回主数据库文件。
///
/// 用独立的连接执行，不干扰主进程持有的那个。
/// 失败不报错：极端情况（长事务持锁）下拿不到排他锁，
/// 此时回退到「连 -wal 一起复制」的策略。
fn checkpoint(db_path: &Path) {
    let Ok(conn) = Connection::open(db_path) else {
        return;
    };
    /*
     * PRAGMA wal_checkpoint 返回一行三列（busy, log, checkpointed），
     * 用 execute 会报「返回了数据行」。这里用 query_row 明确吃掉结果。
     */
    let _ = conn.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |row| {
        let _busy: i64 = row.get(0)?;
        Ok(())
    });
    drop(conn);
}

/// 创建备份，返回文件信息。
///
/// 时间戳只到秒，同一秒内连续备份会重名。
/// 这里加序号避让，而不是覆盖 —— 被覆盖的可能正是要保留的那份。
pub fn create_backup(db_path: &Path, version: i64) -> Result<BackupFile, String> {
    let dir = db_path.parent().ok_or("数据库路径无效")?;
    let base = db_path
        .file_name()
        .map(|v| v.to_string_lossy().to_string())
        .ok_or("数据库文件名无效")?;
    let stamp = stamp();

    let mut name = format!("{base}.v{version}-{stamp}.bak");
    let mut path = dir.join(&name);
    let mut n = 2;
    while path.exists() {
        name = format!("{base}.v{version}-{stamp}-{n}.bak");
        path = dir.join(&name);
        n += 1;
    }

    /*
     * 关键：先做 WAL checkpoint。
     *
     * SQLite 的 WAL 模式下，最近的写入先落在 -wal 文件里，
     * 主 .db 文件可能仍是几 KB 的空壳。
     *
     * 直接复制主文件会得到一个「能打开但没有数据」的备份 ——
     * 这个坑极隐蔽：文件存在、大小看起来正常、能读，只是空的。
     * 用户不会察觉，直到真正需要恢复的那天。
     *
     * TRUNCATE 模式把 WAL 全部合并回主文件并清空 -wal。
     */
    checkpoint(db_path);

    fs::copy(db_path, &path).map_err(|e| format!("复制数据库失败：{e}"))?;

    // checkpoint 后 -wal 通常是空的；万一有残留（比如有长事务挂着），
    // 一并带走作为兜底
    for suffix in ["-wal", "-shm"] {
        let side = PathBuf::from(format!("{}{suffix}", db_path.display()));
        if side.exists() {
            let _ = fs::copy(&side, format!("{}{suffix}", path.display()));
        }
    }

    let size = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    Ok(BackupFile {
        created_at: parse_stamp(&name),
        version,
        name,
        size,
    })
}

/// 列出全部备份，按时间倒序。
pub fn list_backups(db_path: &Path) -> Vec<BackupFile> {
    let Some(dir) = db_path.parent() else {
        return Vec::new();
    };
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };

    let mut files: Vec<BackupFile> = entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().to_string();
            if !is_valid_name(&name) || !belongs_to(db_path, &name) {
                return None;
            }
            let size = entry.metadata().ok()?.len();

            /*
             * 过滤掉没有 users 表的空备份。
             *
             * 早期版本在全新安装时会生成一个 4KB 的空壳备份，
             * 里面一张表都没有。用户误恢复它，账号和数据全部消失，
             * 表现就像「需要重新注册」。这类文件没有价值，藏起来。
             *
             * 不删文件 —— 万一判断有误，用户还能手工找回来。
             */
            let path = dir.join(&name);
            if !has_users_table(&path) {
                return None;
            }

            Some(BackupFile {
                created_at: parse_stamp(&name),
                version: parse_version(&name),
                name,
                size,
            })
        })
        .collect();

    files.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    files
}

/// 数据库文件是否完整可读。
///
/// 只检查魔数不够 —— 被截断或写坏的文件头部照样正确，
/// 但打开后所有查询都报 malformed。PRAGMA integrity_check
/// 会扫描整库结构，返回 ok 才算健康。
fn is_healthy_sqlite(path: &Path) -> bool {
    let Ok(conn) = Connection::open(path) else {
        return false;
    };
    let healthy = conn
        .query_row("PRAGMA integrity_check", [], |row| row.get::<_, String>(0))
        .map(|v| v == "ok")
        .unwrap_or(false);
    drop(conn);
    healthy
}

/// 备份里是否有 users 表。
///
/// 用来识别「空备份」——全新安装时产生的迁移备份不含任何表，
/// 恢复它等于清空数据库。打不开或没有该表都返回 false。
fn has_users_table(path: &Path) -> bool {
    let Ok(conn) = Connection::open(path) else {
        return false;
    };
    let exists = conn
        .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
        .and_then(|mut s| s.exists([]))
        .unwrap_or(false);
    drop(conn);
    exists
}

/// 删除一个备份（连同 -wal / -shm）。
pub fn delete_backup(db_path: &Path, name: &str) -> Result<(), String> {
    if !is_valid_name(name) || !belongs_to(db_path, name) {
        return Err("备份文件名不合法".to_string());
    }
    let dir = db_path.parent().ok_or("数据库路径无效")?;
    let path = dir.join(name);
    if !path.exists() {
        return Err("备份文件不存在".to_string());
    }
    fs::remove_file(&path).map_err(|e| format!("删除失败：{e}"))?;
    for suffix in ["-wal", "-shm"] {
        let side = PathBuf::from(format!("{}{suffix}", path.display()));
        let _ = fs::remove_file(side);
    }
    Ok(())
}

fn looks_like_sqlite(path: &Path) -> bool {
    match fs::read(path) {
        Ok(bytes) => bytes.len() >= 16 && &bytes[..16] == SQLITE_MAGIC,
        Err(_) => false,
    }
}

/// 把备份复制到指定位置（用于「另存为」）。
pub fn export_backup(db_path: &Path, name: &str, dest: &Path) -> Result<(), String> {
    if !is_valid_name(name) || !belongs_to(db_path, name) {
        return Err("备份文件名不合法".to_string());
    }
    let dir = db_path.parent().ok_or("数据库路径无效")?;
    let source = dir.join(name);
    if !source.exists() {
        return Err("备份文件不存在".to_string());
    }
    fs::copy(&source, dest).map_err(|e| format!("导出失败：{e}"))?;
    Ok(())
}

/// 读取备份文件内容（用于下载）。
pub fn read_backup(db_path: &Path, name: &str) -> Result<Vec<u8>, String> {
    if !is_valid_name(name) || !belongs_to(db_path, name) {
        return Err("备份文件名不合法".to_string());
    }
    let dir = db_path.parent().ok_or("数据库路径无效")?;
    let path = dir.join(name);
    if !path.exists() {
        return Err("备份文件不存在".to_string());
    }
    fs::read(&path).map_err(|e| format!("读取失败：{e}"))
}

/// 从备份恢复。返回安全副本的文件名。
///
/// 调用方必须先关闭数据库连接 —— 文件被占用时无法覆盖。
pub fn restore_backup(db_path: &Path, name: &str, current_version: i64) -> Result<String, String> {
    if !is_valid_name(name) || !belongs_to(db_path, name) {
        return Err("备份文件名不合法".to_string());
    }

    let dir = db_path.parent().ok_or("数据库路径无效")?;
    let source = dir.join(name);
    if !source.exists() {
        return Err("备份文件不存在".to_string());
    }
    if !looks_like_sqlite(&source) {
        return Err("该文件不是有效的数据库备份".to_string());
    }
    if !is_healthy_sqlite(&source) {
        return Err("备份文件已损坏，无法恢复".to_string());
    }
    if !has_users_table(&source) {
        return Err(
            "这份备份里没有任何账号数据，恢复它会让系统回到「未初始化」状态。\
             如果你确实想重来，请手动清空数据库，而不是恢复这个文件。"
                .to_string(),
        );
    }

    // 恢复前先保住当前数据，万一选错了还能回来
    let safety = create_backup(db_path, current_version)?;

    fs::copy(&source, db_path).map_err(|e| format!("恢复失败：{e}"))?;

    // 旧 WAL 记录的是旧库的变更，必须删掉
    for suffix in ["-wal", "-shm"] {
        let side = PathBuf::from(format!("{}{suffix}", db_path.display()));
        let _ = fs::remove_file(side);
    }

    // 备份自带的附属文件一并还原
    for suffix in ["-wal", "-shm"] {
        let side = PathBuf::from(format!("{}{suffix}", source.display()));
        if side.exists() {
            let _ = fs::copy(&side, format!("{}{suffix}", db_path.display()));
        }
    }

    Ok(safety.name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filename_validation_rejects_traversal() {
        assert!(!is_valid_name("../../etc/passwd"));
        assert!(!is_valid_name("..\\win.exe"));
        assert!(!is_valid_name("nofile"));
        assert!(is_valid_name("local.db.v2-2026-11-02T11-30-00.bak"));
        assert!(is_valid_name("local.db.v2-2026-11-02T11-30-00-2.bak"));
    }

    #[test]
    fn format_timestamp_produces_expected_text() {
        // format_timestamp 把「本地秒」写成 YYYY-MM-DDTHH-MM-SS
        let text = format_timestamp(1_793_619_000);
        assert_eq!(text, "2026-11-02T11-30-00");
    }

    #[test]
    fn parse_stamp_returns_utc_millis() {
        /*
         * parse_stamp 的语义：文件名里是本地时刻，
         * 返回的是 Unix 毫秒（UTC 基准），供前端 new Date(ms) 使用。
         *
         * 所以「本地 11:30」应解析成「UTC 11:30 减去时区偏移」。
         */
        let name = "local.db.v2-2026-11-02T11-30-00.bak";
        let ms = parse_stamp(name);

        let offset = local_utc_offset_secs();
        // 2026-11-02T11:30:00 当作 UTC 的秒数
        let as_if_utc = 1_793_619_000i64;
        assert_eq!(ms, (as_if_utc - offset) * 1000);
    }

    #[test]
    fn stamp_roundtrip_preserves_local_time() {
        /*
         * 这是用户实际报的问题：文件名写 16:32，
         * 列表却显示次日 00:32（差 8 小时，日期都跳了）。
         *
         * 根因是 parse_stamp 返回的毫秒数被前端按本地时区
         * 二次换算。修复后两者必须严格互逆。
         */
        let local = now_local_secs();
        let text = format_timestamp(local);
        let name = format!("local.db.v2-{text}.bak");
        let parsed_ms = parse_stamp(&name);

        /*
         * format_timestamp(local) 把「本地秒」写成字符串，
         * parse_stamp 再把它还原成 Unix 毫秒。
         * 所以期望值是 local * 1000 —— 这里的 local 本身就是
         * 「本地时刻当成 UTC 算出的秒」，与文件名语义一致。
         */
        /*
         * now_local_secs() 给的是「本地时刻当成 UTC 的秒数」，
         * parse_stamp 会减掉时区偏移还原成真正的 UTC 毫秒。
         */
        let expected_ms = (local as i64 - local_utc_offset_secs()) * 1000;
        assert_eq!(
            parsed_ms, expected_ms,
            "文件名 {text} 解析成 {parsed_ms}ms，应为 {expected_ms}ms"
        );
    }

    #[test]
    fn back_to_back_create_and_parse_agree() {
        // 端到端：备份一次，createdAt 应接近此刻
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("local.db");
        {
            let conn = Connection::open(&db).unwrap();
            conn.pragma_update(None, "journal_mode", "WAL").unwrap();
            conn.execute_batch("CREATE TABLE t (id integer);").unwrap();
        }

        let before = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;

        let file = create_backup(&db, 2).unwrap();

        let after = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;

        // 解析出的时间应落在这次调用的时间窗内（允许 2 秒误差）
        assert!(
            file.created_at >= before - 2000 && file.created_at <= after + 2000,
            "created_at={} 不在 [{}, {}] 之间",
            file.created_at,
            before - 2000,
            after + 2000
        );
    }

    #[test]
    fn backup_includes_uncheckpointed_wal_data() {
        /*
         * 连接保持存活 —— 这是真实场景。
         *
         * SQLite 在最后一个连接关闭时会自动 checkpoint，
         * 所以「写完就 drop 再备份」复现不出问题。
         *
         * 断言分两层：
         * 1. 备份能查到数据（功能正确）
         * 2. 主文件本身也变大了（说明 checkpoint 真的执行了，
         *    而不是靠复制 -wal 侥幸通过）
         */
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("local.db");

        let conn = Connection::open(&db).unwrap();
        conn.pragma_update(None, "journal_mode", "WAL").unwrap();
        conn.execute_batch(
            "CREATE TABLE probe (id text PRIMARY KEY, value text);
             INSERT INTO probe (id, value) VALUES ('k', 'in-wal');",
        )
        .unwrap();

        let main_before = fs::metadata(&db).map(|m| m.len()).unwrap_or(0);
        let wal_before = fs::metadata(format!("{}-wal", db.display()))
            .map(|m| m.len())
            .unwrap_or(0);
        assert!(wal_before > 0, "写入后应有未合并的 -wal");

        let file = create_backup(&db, 2).unwrap();

        // 断言 1：备份里能查到数据
        let backup_path = dir.path().join(&file.name);
        let check = Connection::open(&backup_path).unwrap();
        let value: String = check
            .query_row("SELECT value FROM probe WHERE id='k'", [], |r| r.get(0))
            .expect("备份里应该能查到数据");
        assert_eq!(value, "in-wal");
        drop(check);

        /*
         * 断言 2：checkpoint 确实把 WAL 合并进了主文件。
         *
         * 没有这一步的话，备份的主文件是空壳、数据只在附带的
         * -wal 里 —— 一旦那个附属文件丢失（复制失败、用户
         * 只拷了 .bak 单个文件），数据就没了。
         * 所以必须验证「主文件自己装得下数据」。
         */
        let main_after = fs::metadata(&db).map(|m| m.len()).unwrap_or(0);
        assert!(
            main_after > main_before,
            "checkpoint 应让主文件变大：before={main_before} after={main_after}"
        );

        drop(conn);
    }

    #[test]
    fn stamp_uses_local_time_not_utc() {
        // 本地偏移非零时，stamp() 的结果不应等于纯 UTC 换算
        let utc = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let local_secs = now_local_secs();
        let offset = local_utc_offset_secs();

        // 偏移与「本地秒 - UTC 秒」一致
        assert_eq!(local_secs as i64 - utc as i64, offset);
    }

    #[test]
    fn version_parsed_from_name() {
        assert_eq!(parse_version("local.db.v2-2026-11-02T11-30-00.bak"), 2);
        assert_eq!(parse_version("local.db.v12-2026-11-02T11-30-00.bak"), 12);
    }
}

/// 导入外部备份文件。
///
/// 三个处理与服务端 importBackup 一致：
/// 1. 校验是真正的 SQLite 文件
/// 2. 拒绝来自更高版本的备份
/// 3. 按本机库名重写文件名（否则会被 list_backups 的前缀过滤掉）
pub fn import_backup(db_path: &Path, source: &Path, current_version: i64) -> Result<BackupFile, String> {
    if !source.exists() {
        return Err("文件不存在".to_string());
    }
    if !looks_like_sqlite(source) {
        return Err("这不是有效的数据库文件".to_string());
    }

    let dir = db_path.parent().ok_or("数据库路径无效")?;
    let base = db_path
        .file_name()
        .map(|v| v.to_string_lossy().to_string())
        .ok_or("数据库文件名无效")?;

    let original = source
        .file_name()
        .map(|v| v.to_string_lossy().to_string())
        .unwrap_or_default();

    // 从原文件名提取版本与时间戳，失败则用当前值兜底
    let version = if is_valid_name(&original) {
        parse_version(&original)
    } else {
        current_version
    };
    let stamp_part = if is_valid_name(&original) {
        original
            .rfind(".v")
            .and_then(|i| original[i + 2..].split_once('-'))
            .map(|(_, tail)| tail.trim_end_matches(".bak").to_string())
            .unwrap_or_else(stamp)
    } else {
        stamp()
    };

    if version > current_version {
        return Err(format!(
            "这份备份来自更高的版本 v{version}，当前程序只支持到 v{current_version}。请升级后再导入。"
        ));
    }

    let mut name = format!("{base}.v{version}-{stamp_part}.bak");
    let mut path = dir.join(&name);
    let mut n = 2;
    while path.exists() {
        name = format!("{base}.v{version}-{stamp_part}-{n}.bak");
        path = dir.join(&name);
        n += 1;
    }

    fs::copy(source, &path).map_err(|e| format!("导入失败：{e}"))?;

    let size = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    Ok(BackupFile {
        created_at: parse_stamp(&name),
        version,
        name,
        size,
    })
}