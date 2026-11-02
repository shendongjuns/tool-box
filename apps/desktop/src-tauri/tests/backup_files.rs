//! 备份文件的端到端验证（真实文件系统）。
//!
//! 与 packages/data/test/backup.test.ts 覆盖同样场景，
//! 保证两端行为一致。

use std::fs;
use std::path::PathBuf;

use tempfile::TempDir;

// 通过 lib 暴露的函数路径引用
use toolbox_desktop_lib::backup;

fn make_db(dir: &TempDir, marker: &str) -> PathBuf {
    let path = dir.path().join("local.db");
    // 写一个最小合法 SQLite 文件头 + 内容
    let mut bytes = b"SQLite format 3\0".to_vec();
    bytes.extend_from_slice(marker.as_bytes());
    fs::write(&path, bytes).unwrap();
    path
}

#[test]
fn create_and_list() {
    let dir = TempDir::new().unwrap();
    let db = make_db(&dir, "hello");

    let file = backup::create_backup(&db, 2).unwrap();
    assert!(file.name.starts_with("local.db.v2-"));
    assert!(file.name.ends_with(".bak"));
    assert!(file.size > 0);

    let list = backup::list_backups(&db);
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].name, file.name);
    assert_eq!(list[0].version, 2);
}

#[test]
fn same_second_does_not_overwrite() {
    let dir = TempDir::new().unwrap();
    let db = make_db(&dir, "x");

    let a = backup::create_backup(&db, 2).unwrap();
    let b = backup::create_backup(&db, 2).unwrap();

    // 同一秒内两次备份必须产生两个不同文件
    assert_ne!(a.name, b.name);
    assert_eq!(backup::list_backups(&db).len(), 2);
}

#[test]
fn restore_roundtrip() {
    let dir = TempDir::new().unwrap();
    let db = make_db(&dir, "original");

    let file = backup::create_backup(&db, 2).unwrap();

    // 改掉内容
    fs::write(&db, b"SQLite format 3\0changed").unwrap();
    assert!(fs::read(&db).unwrap().ends_with(b"changed"));

    backup::restore_backup(&db, &file.name, 2).unwrap();

    assert!(fs::read(&db).unwrap().ends_with(b"original"));
}

#[test]
fn restore_creates_safety_copy() {
    let dir = TempDir::new().unwrap();
    let db = make_db(&dir, "before");
    let file = backup::create_backup(&db, 2).unwrap();
    let count_before = backup::list_backups(&db).len();

    let safety = backup::restore_backup(&db, &file.name, 2).unwrap();

    assert!(safety.ends_with(".bak"));
    assert_eq!(backup::list_backups(&db).len(), count_before + 1);
}

#[test]
fn reject_non_sqlite_file() {
    let dir = TempDir::new().unwrap();
    let db = make_db(&dir, "x");

    let fake = "local.db.v2-2026-01-01T00-00-00.bak";
    fs::write(dir.path().join(fake), b"not a database").unwrap();

    let err = backup::restore_backup(&db, fake, 2).unwrap_err();
    assert!(err.contains("不是有效的数据库备份"), "got: {err}");
}

#[test]
fn reject_path_traversal() {
    let dir = TempDir::new().unwrap();
    let db = make_db(&dir, "x");

    let err = backup::restore_backup(&db, "../../evil.bak", 2).unwrap_err();
    assert!(err.contains("不合法"), "got: {err}");
}

#[test]
fn delete_removes_only_target() {
    let dir = TempDir::new().unwrap();
    let db = make_db(&dir, "x");

    let a = backup::create_backup(&db, 2).unwrap();
    let b = backup::create_backup(&db, 2).unwrap();

    backup::delete_backup(&db, &a.name).unwrap();

    let list = backup::list_backups(&db);
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].name, b.name);
}

#[test]
fn other_databases_backups_ignored() {
    let dir = TempDir::new().unwrap();
    let db = make_db(&dir, "x");
    backup::create_backup(&db, 2).unwrap();

    // 另一个库的备份不该混进来
    fs::write(
        dir.path().join("other.db.v2-2026-01-01T00-00-00.bak"),
        b"SQLite format 3\0",
    )
    .unwrap();

    assert_eq!(backup::list_backups(&db).len(), 1);
}
