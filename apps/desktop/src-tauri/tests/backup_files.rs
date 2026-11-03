//! 备份文件的端到端验证（真实文件系统）。
//!
//! 与 packages/data/test/backup.test.ts 覆盖同样场景，
//! 保证两端行为一致。

use std::fs;
use std::path::PathBuf;

use tempfile::TempDir;

// 通过 lib 暴露的函数路径引用
use toolbox_desktop_lib::backup;

/// 建一个最小的合法 SQLite 库，带 users 表。
///
/// 必须是真的 SQLite 文件（不是伪造头部）—— 恢复与列表都会
/// 做 integrity_check 与 users 表存在性检查。
fn make_db(dir: &TempDir, marker: &str) -> PathBuf {
    let path = dir.path().join("local.db");
    let conn = rusqlite::Connection::open(&path).unwrap();
    conn.execute_batch(&format!(
        "CREATE TABLE users (id text PRIMARY KEY, username text);
         CREATE TABLE probe (id text PRIMARY KEY, value text);
         INSERT INTO probe (id, value) VALUES ('k', '{marker}');"
    ))
    .unwrap();
    conn.close().ok();
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

    /*
     * 用真实 SQL 修改数据，而不是伪造字节。
     *
     * 伪造一个「头部正确、内容垃圾」的文件会被 restore_backup
     * 的完整性检查正确拒绝 —— 那是期望行为，不是这个测试要验的。
     */
    {
        let conn = rusqlite::Connection::open(&db).unwrap();
        conn.execute("UPDATE probe SET value='changed' WHERE id='k'", [])
            .unwrap();
    }

    backup::restore_backup(&db, &file.name, 2).unwrap();

    let conn = rusqlite::Connection::open(&db).unwrap();
    let value: String = conn
        .query_row("SELECT value FROM probe WHERE id='k'", [], |r| r.get(0))
        .unwrap();
    assert_eq!(value, "original", "恢复后应回到备份时的数据");
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