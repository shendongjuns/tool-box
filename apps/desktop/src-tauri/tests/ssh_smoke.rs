//! SSH 连接的冒烟测试。
//!
//! 需要环境变量指向一个可连接的 SSH 服务器，未设置时跳过：
//!   SSH_TEST_HOST / SSH_TEST_PORT / SSH_TEST_USER
//!   SSH_TEST_PASS      密码认证
//!   SSH_TEST_KEY_FILE  私钥认证（优先）
//!
//! 覆盖：TCP 连接 → 密钥交换 → 认证 → 打开会话 → 执行命令 → 读取输出。

use std::sync::Arc;
use std::time::Duration;

use russh::client::{self, Handle};
use russh::keys::PrivateKeyWithHashAlg;
use russh::ChannelMsg;

struct AcceptAll;

impl client::Handler for AcceptAll {
    type Error = russh::Error;

    fn check_server_key(
        &mut self,
        _key: &russh::keys::ssh_key::PublicKey,
    ) -> impl std::future::Future<Output = Result<bool, Self::Error>> + Send {
        async { Ok(true) }
    }
}

#[tokio::test]
async fn connect_and_exec() {
    let Ok(host) = std::env::var("SSH_TEST_HOST") else {
        eprintln!("跳过：未设置 SSH_TEST_HOST");
        return;
    };
    let port: u16 = std::env::var("SSH_TEST_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(22);
    let user = std::env::var("SSH_TEST_USER").unwrap_or_else(|_| "root".to_string());

    let config = Arc::new(client::Config {
        inactivity_timeout: None,
        ..Default::default()
    });
    let mut handle: Handle<AcceptAll> = client::connect(config, (host.as_str(), port), AcceptAll)
        .await
        .expect("连接失败");

    let ok = if let Ok(key_file) = std::env::var("SSH_TEST_KEY_FILE") {
        let pem = std::fs::read_to_string(&key_file).expect("读取私钥失败");
        let key = russh::keys::decode_secret_key(&pem, None).expect("私钥解析失败");
        // 与 ssh.rs 中保持一致：RSA 必须指定 SHA-256
        let hash = match key.algorithm() {
            russh::keys::ssh_key::Algorithm::Rsa { .. } => Some(russh::keys::HashAlg::Sha256),
            _ => None,
        };
        let with_alg = PrivateKeyWithHashAlg::new(Arc::new(key), hash);
        handle
            .authenticate_publickey(&user, with_alg)
            .await
            .expect("认证请求失败")
            .success()
    } else {
        let pass = std::env::var("SSH_TEST_PASS").unwrap_or_default();
        handle
            .authenticate_password(&user, &pass)
            .await
            .expect("认证请求失败")
            .success()
    };
    assert!(ok, "认证失败");

    let handle = Arc::new(handle);
    let mut channel = handle.channel_open_session().await.expect("打开会话失败");
    channel.exec(true, b"echo ssh-ok").await.expect("执行失败");

    let mut out = Vec::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        tokio::select! {
            msg = channel.wait() => {
                match msg {
                    Some(ChannelMsg::Data { data }) => out.extend_from_slice(&data),
                    Some(ChannelMsg::Eof) | Some(ChannelMsg::Close) | None => break,
                    _ => {}
                }
            }
            _ = tokio::time::sleep_until(deadline) => panic!("执行超时"),
        }
    }

    let text = String::from_utf8_lossy(&out);
    assert!(text.contains("ssh-ok"), "输出异常: {text}");
    eprintln!("SSH 连接正常，输出: {}", text.trim());
}
