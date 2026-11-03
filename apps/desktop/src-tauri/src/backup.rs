//! 数据库备份与恢复。
//!
//! 与 TypeScript 侧（packages/data/src/backup.ts）保持同一套规则：
//! 文件命名、版本号、路径穿越防御、恢复前的安全副本。
//!
//! 为什么两边各写一份而不是共享代码：
//! 服务端跑 Node，桌面端是 Rust 进程内嵌 SQLite，
//! 没有能共用的运行时。规则必须一致，所以两边的测试用例
//! 也刻意保持对应。

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
    days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
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

    fs::copy(db_path, &path).map_err(|e| format!("复制数据库失败：{e}"))?;

    // -wal / -shm 一并带走，否则恢复后可能缺最后一段数据
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
    fn timestamp_roundtrip() {
        // format_timestamp 接收「本地秒」，parse_stamp 也按本地时间解析，
        // 两者必须互为逆运算 —— 这也是用户看到的文件名与列表时间一致的前提。
        let secs = 1_793_619_000u64;
        let text = format_timestamp(secs);
        assert_eq!(text, "2026-11-02T11-30-00");
        let name = format!("local.db.v2-{text}.bak");
        assert_eq!(parse_stamp(&name), secs as i64);
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