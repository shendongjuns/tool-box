//! 监控采集冒烟测试。
//!
//! 目标环境是 Linux 服务器（读取 /proc）。Windows 的 OpenSSH 默认 shell 是
//! cmd.exe，不支持 `echo '==X=='` 这种语法，因此这里只验证「命令能被下达
//! 并返回输出」，分段标记的断言仅在 POSIX 环境执行。

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

const METRICS_COMMAND: &str = concat!(
    "cat /proc/stat 2>/dev/null || true; ",
    "echo '==MEM=='; cat /proc/meminfo 2>/dev/null || true; ",
    "echo '==DF=='; df -P -B1 2>/dev/null || true; ",
    "echo '==NET=='; cat /proc/net/dev 2>/dev/null || true; ",
    "echo '==LOAD=='; cat /proc/loadavg 2>/dev/null || true; ",
    "echo '==NPROC=='; nproc 2>/dev/null || true; ",
    "echo '==PS=='; ps -eo pid,%cpu,%mem 2>/dev/null | head -5 || true; ",
    "echo '==GPU=='; nvidia-smi -L 2>/dev/null || true; ",
    "echo '==NPU=='; command -v npu-smi >/dev/null 2>&1 && npu-smi info 2>/dev/null; true",
);

async fn exec(handle: &Arc<Handle<AcceptAll>>, cmd: &str) -> String {
    let mut ch = handle.channel_open_session().await.expect("open");
    ch.exec(true, cmd.as_bytes()).await.expect("exec");
    let mut out = Vec::new();
    let dl = tokio::time::Instant::now() + Duration::from_secs(15);
    loop {
        tokio::select! {
            msg = ch.wait() => match msg {
                Some(ChannelMsg::Data { data }) => out.extend_from_slice(&data),
                Some(ChannelMsg::ExtendedData { data, .. }) => out.extend_from_slice(&data),
                Some(ChannelMsg::Eof) | Some(ChannelMsg::Close) | None => break,
                _ => {}
            },
            _ = tokio::time::sleep_until(dl) => break,
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[tokio::test]
async fn collect_metrics_sections() {
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

    if let Ok(key_file) = std::env::var("SSH_TEST_KEY_FILE") {
        let pem = std::fs::read_to_string(&key_file).expect("read key");
        let key = russh::keys::decode_secret_key(&pem, None).expect("parse key");
        let hash = match key.algorithm() {
            russh::keys::ssh_key::Algorithm::Rsa { .. } => Some(russh::keys::HashAlg::Sha256),
            _ => None,
        };
        handle
            .authenticate_publickey(&user, PrivateKeyWithHashAlg::new(Arc::new(key), hash))
            .await
            .expect("auth")
            .success();
    } else {
        let pass = std::env::var("SSH_TEST_PASS").unwrap_or_default();
        handle
            .authenticate_password(&user, &pass)
            .await
            .expect("auth")
            .success();
    }

    let handle = Arc::new(handle);

    // 先探测远端是否为 POSIX（/proc 存在）
    let probe = exec(&handle, "test -r /proc/stat && echo POSIX || echo OTHER").await;
    let is_posix = probe.contains("POSIX");

    let output = exec(&handle, METRICS_COMMAND).await;
    eprintln!(
        "目标平台: {} | 输出 {} 字节",
        if is_posix { "POSIX" } else { "非 POSIX" },
        output.len()
    );

    if is_posix {
        for marker in ["==MEM==", "==DF==", "==NET==", "==LOAD==", "==NPROC==", "==PS=="] {
            assert!(output.contains(marker), "缺少分段 {marker}");
        }
        assert!(
            output.contains("MemTotal:"),
            "缺少 MemTotal 行，输出片段: {}",
            &output[..output.len().min(200)]
        );
        eprintln!("POSIX 分段与内容验证通过");
    } else {
        // 非 POSIX（如 Windows cmd）：只要求命令能落下并返回，不校验内容
        eprintln!("非 POSIX 环境，跳过内容断言（该功能面向 Linux 服务器）");
    }
}
