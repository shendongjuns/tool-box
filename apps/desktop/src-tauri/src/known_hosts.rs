//! SSH 主机密钥校验（TOFU：Trust On First Use）。
//!
//! 为什么必须有这个模块：
//! SSH 加密只保证「链路」安全，不保证「对端身份」。不校验主机密钥时，
//! 任何能劫持 DNS / ARP / 路由的人都能伪装成目标服务器，
//! 拿到用户输入的 SSH 密码与私钥 —— 这是 SSH 最经典的中间人攻击。
//!
//! 策略：
//! - 首次连接（known_hosts 里没有记录）→ 记录指纹并放行
//! - 后续连接指纹一致 → 放行
//! - 指纹变化 → **拒绝**，返回明确错误，由用户显式决定是否信任新指纹
//!
//! 存储：`data/known_hosts.json`，格式 { "host:port": { "algo": "...", "fingerprint": "..." } }

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// 一条主机记录。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostRecord {
    /// 密钥算法名，如 `ssh-ed25519`、`rsa-sha2-256`
    pub algorithm: String,
    /// OpenSSH 风格指纹：`SHA256:base64(sha256(key_blob))`
    pub fingerprint: String,
}

/// known_hosts 存储。
pub struct KnownHosts {
    path: PathBuf,
    /// host:port -> 记录
    entries: Mutex<HashMap<String, HostRecord>>,
}

impl KnownHosts {
    /// 从磁盘加载；文件不存在时创建空表。
    pub fn load(path: PathBuf) -> Self {
        let entries = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str::<HashMap<String, HostRecord>>(&text).ok())
            .unwrap_or_default();

        Self {
            path,
            entries: Mutex::new(entries),
        }
    }

    /// 校验指纹。
    ///
    /// 返回 Ok(true) 表示可以继续；Ok(false) 表示**指纹变化，必须拒绝**。
    pub fn verify(&self, host_key: &str, record: &HostRecord) -> bool {
        let mut entries = match self.entries.lock() {
            Ok(guard) => guard,
            // 锁中毒时保守拒绝，宁可不连也不放行未知主机
            Err(_) => return false,
        };

        match entries.get(host_key) {
            // 首次连接：记录并放行
            None => {
                entries.insert(host_key.to_string(), record.clone());
                self.persist(&entries);
                true
            }
            // 指纹一致：放行
            Some(existing) if existing.fingerprint == record.fingerprint => true,
            // 指纹变化：拒绝（不自动覆盖，避免静默接受中间人）
            Some(_) => false,
        }
    }

    /// 用户显式信任新指纹时调用（覆盖旧记录）。
    pub fn trust(&self, host_key: &str, record: HostRecord) {
        if let Ok(mut entries) = self.entries.lock() {
            entries.insert(host_key.to_string(), record);
            self.persist(&entries);
        }
    }

    /// 读取某主机的已保存记录。
    pub fn get(&self, host_key: &str) -> Option<HostRecord> {
        self.entries.lock().ok()?.get(host_key).cloned()
    }

    /// 写回磁盘。失败只记日志，不影响连接流程。
    fn persist(&self, entries: &HashMap<String, HostRecord>) {
        if let Some(parent) = self.path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(text) = serde_json::to_string_pretty(entries) {
            let _ = std::fs::write(&self.path, text);
        }
    }
}

/// 计算 OpenSSH 风格的指纹：`SHA256:base64(sha256(wire_blob))`。
///
/// 与 `ssh-keygen -lf` 的输出一致，便于用户对照。
pub fn fingerprint_of(key: &russh::keys::PublicKey) -> HostRecord {
    use base64::Engine as _;

    let algorithm = key.algorithm().to_string();
    // ssh-key 的 encode 产出 SSH wire format（含算法名前缀），与 OpenSSH 一致
    let blob = key.to_bytes().unwrap_or_default();
    let digest = Sha256::digest(&blob);
    let encoded = base64::engine::general_purpose::STANDARD.encode(digest);

    HostRecord {
        algorithm,
        // OpenSSH 会去掉 base64 的 = 填充
        fingerprint: format!("SHA256:{}", encoded.trim_end_matches('=')),
    }
}

/// 把连接受到的 `PublicKeyOrCertificate` 归一成公钥。
pub fn public_key_of(
    key: &russh::keys::PublicKeyOrCertificate,
) -> Option<&russh::keys::PublicKey> {
    match key {
        russh::keys::PublicKeyOrCertificate::PublicKey { key, .. } => Some(key),
        // 证书模式暂不支持：直接拒绝比放行安全
        russh::keys::PublicKeyOrCertificate::Certificate(_) => None,
    }
}
