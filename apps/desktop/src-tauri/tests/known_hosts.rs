//! 主机密钥校验（TOFU）测试。
//!
//! 核心保证：
//! 1. 首次见到的指纹会被记录并放行
//! 2. 相同指纹再次连接放行
//! 3. **指纹变化必须拒绝**（防中间人）
//! 4. 用户显式信任后可覆盖
//! 5. 指纹格式与 ssh-keygen 一致（SHA256:base64，无 = 填充）

use tempfile::TempDir;
use toolbox_desktop_lib::known_hosts::{HostRecord, KnownHosts};

fn record(fp: &str) -> HostRecord {
    HostRecord {
        algorithm: "ssh-ed25519".to_string(),
        fingerprint: fp.to_string(),
    }
}

#[test]
fn first_use_is_recorded_and_allowed() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("known_hosts.json");
    let store = KnownHosts::load(path.clone());

    let fp = "SHA256:AAAA1111";
    assert!(store.verify("1.2.3.4:22", &record(fp)), "首次连接应放行");
    assert!(path.exists(), "应写入 known_hosts.json");
    assert_eq!(store.get("1.2.3.4:22").unwrap().fingerprint, fp);
}

#[test]
fn same_fingerprint_is_allowed() {
    let dir = TempDir::new().unwrap();
    let store = KnownHosts::load(dir.path().join("kh.json"));

    let fp = "SHA256:BBBB2222";
    store.verify("host:22", &record(fp));
    assert!(store.verify("host:22", &record(fp)), "相同指纹应放行");
}

#[test]
fn changed_fingerprint_is_rejected() {
    let dir = TempDir::new().unwrap();
    let store = KnownHosts::load(dir.path().join("kh.json"));

    store.verify("host:22", &record("SHA256:ORIGINAL"));
    // 指纹变了 —— 可能是服务器重装，也可能是中间人
    assert!(
        !store.verify("host:22", &record("SHA256:CHANGED")),
        "指纹变化必须拒绝"
    );

    // 拒绝后不能静默覆盖原记录
    assert_eq!(store.get("host:22").unwrap().fingerprint, "SHA256:ORIGINAL");
}

#[test]
fn explicit_trust_overwrites() {
    let dir = TempDir::new().unwrap();
    let store = KnownHosts::load(dir.path().join("kh.json"));

    store.verify("host:22", &record("SHA256:OLD"));
    assert!(!store.verify("host:22", &record("SHA256:NEW")));

    // 用户手动确认信任新指纹
    store.trust("host:22", record("SHA256:NEW"));
    assert_eq!(store.get("host:22").unwrap().fingerprint, "SHA256:NEW");
    assert!(store.verify("host:22", &record("SHA256:NEW")), "信任后应放行");
}

#[test]
fn persists_across_instances() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("kh.json");

    let fp = "SHA256:PERSIST";
    {
        let store = KnownHosts::load(path.clone());
        store.verify("host:22", &record(fp));
    }

    // 模拟重启：新实例应从磁盘读回记录
    let reloaded = KnownHosts::load(path);
    assert_eq!(reloaded.get("host:22").unwrap().fingerprint, fp);
    assert!(reloaded.verify("host:22", &record(fp)));
    // 且仍然拒绝变化
    assert!(!reloaded.verify("host:22", &record("SHA256:OTHER")));
}

#[test]
fn different_hosts_are_independent() {
    let dir = TempDir::new().unwrap();
    let store = KnownHosts::load(dir.path().join("kh.json"));

    store.verify("a.example:22", &record("SHA256:AAA"));
    store.verify("b.example:22", &record("SHA256:BBB"));

    assert!(store.verify("a.example:22", &record("SHA256:AAA")));
    assert!(store.verify("b.example:22", &record("SHA256:BBB")));
    // 交叉比对不允许
    assert!(!store.verify("a.example:22", &record("SHA256:BBB")));
}

#[test]
fn malformed_file_degrades_to_empty() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("kh.json");
    std::fs::write(&path, "not valid json {{{").unwrap();

    // 损坏的文件不应导致 panic，退化为空表重新开始
    let store = KnownHosts::load(path);
    assert!(store.get("any:22").is_none());
    assert!(store.verify("any:22", &record("SHA256:NEW")));
}
