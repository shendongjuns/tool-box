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
fn stamp() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format_timestamp(now)
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
        // 2026-11-02T11:30:00Z = 1793619000
        let secs = 1_793_619_000u64;
        let text = format_timestamp(secs);
        assert_eq!(text, "2026-11-02T11-30-00");
        let name = format!("local.db.v2-{text}.bak");
        assert_eq!(parse_stamp(&name), secs as i64);
    }

    #[test]
    fn version_parsed_from_name() {
        assert_eq!(parse_version("local.db.v2-2026-11-02T11-30-00.bak"), 2);
        assert_eq!(parse_version("local.db.v12-2026-11-02T11-30-00.bak"), 12);
    }
}
