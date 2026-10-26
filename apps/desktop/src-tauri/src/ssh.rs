//! SSH / SFTP 远程连接管理。
//!
//! 为什么必须在 Rust 侧：WebView 里的 JS 无法建立原始 TCP 连接，
//! 浏览器的安全模型不允许。所有 SSH 流量必须由 Rust 发起。
//!
//! 结构：
//! - 每个连接一个会话 id，存进全局 registry
//! - 读写各用一个任务：读任务把远端输出合并后 emit 给前端，
//!   写任务从 mpsc 取前端输入写入远端
//! - 输出按帧合并（默认 16ms），避免大输出时事件洪泛卡住 WebView

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use russh::client::{self, Handle};
use russh::keys::PrivateKeyWithHashAlg;
use russh::ChannelMsg;
use serde::{Deserialize, Serialize};
use tauri::Emitter;
use tokio::sync::{mpsc, Mutex};

/// 输出合并窗口。终端刷屏时把这段时间内的数据攒成一帧。
const FLUSH_INTERVAL: Duration = Duration::from_millis(16);

pub struct SshSession {
    /// 保持连接存活；drop 后连接关闭
    pub handle: Arc<Handle<ClientHandler>>,
    input_tx: mpsc::Sender<Vec<u8>>,
    resize_tx: mpsc::Sender<(u32, u32)>,
    close_tx: mpsc::Sender<()>,
}

pub type Sessions = Arc<Mutex<HashMap<String, SshSession>>>;

#[derive(Default)]
pub struct SshState {
    pub sessions: Sessions,
}

impl SshState {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

pub struct ClientHandler;

impl client::Handler for ClientHandler {
    type Error = russh::Error;

    /// 接受任意主机密钥。
    ///
    /// TODO(严格模式)：持久化 known_hosts 并在指纹变化时告警。
    /// 当前优先保证可用性，界面上会提示「首次连接请自行确认主机身份」。
    fn check_server_key(
        &mut self,
        _server_public_key: &russh::keys::ssh_key::PublicKey,
    ) -> impl std::future::Future<Output = Result<bool, Self::Error>> + Send {
        async { Ok(true) }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectConfig {
    pub session_id: String,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_type: String,
    pub password: Option<String>,
    pub private_key: Option<String>,
    pub passphrase: Option<String>,
    pub cols: u32,
    pub rows: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectResult {
    pub session_id: String,
}

/// 建立连接并打开交互式 shell。
pub async fn connect(
    state: SshState,
    config: ConnectConfig,
    app: tauri::AppHandle,
) -> Result<ConnectResult, String> {
    let ssh_config = Arc::new(client::Config {
        inactivity_timeout: None,
        keepalive_interval: Some(Duration::from_secs(15)),
        keepalive_max: 3,
        ..Default::default()
    });

    let mut handle = client::connect(
        ssh_config,
        (config.host.as_str(), config.port),
        ClientHandler,
    )
    .await
    .map_err(|e| format!("连接失败：{e}"))?;

    let auth_ok = match config.auth_type.as_str() {
        "password" => handle
            .authenticate_password(&config.username, config.password.as_deref().unwrap_or(""))
            .await
            .map_err(|e| format!("认证失败：{e}"))?
            .success(),
        "key" => {
            let pem = config
                .private_key
                .as_deref()
                .ok_or_else(|| "缺少私钥内容".to_string())?;
            let key = russh::keys::decode_secret_key(pem, config.passphrase.as_deref())
                .map_err(|e| format!("私钥解析失败：{e}"))?;

            /*
             * RSA 私钥必须显式指定 SHA-256。
             *
             * OpenSSH 8.8+ 默认禁用 ssh-rsa（SHA-1）签名，传 None 会走
             * 默认算法并被服务器拒绝，表现为「认证失败」但密码/私钥都正确。
             * 实测：hash=None 失败，Sha256 成功。
             */
            let hash = match key.algorithm() {
                russh::keys::ssh_key::Algorithm::Rsa { .. } => {
                    Some(russh::keys::HashAlg::Sha256)
                }
                _ => None,
            };
            let with_alg = PrivateKeyWithHashAlg::new(Arc::new(key), hash);
            handle
                .authenticate_publickey(&config.username, with_alg)
                .await
                .map_err(|e| format!("认证失败：{e}"))?
                .success()
        }
        other => return Err(format!("不支持的认证方式：{other}")),
    };

    if !auth_ok {
        return Err("认证失败：用户名或凭据不正确".to_string());
    }

    let handle = Arc::new(handle);

    let channel = handle
        .channel_open_session()
        .await
        .map_err(|e| format!("打开会话失败：{e}"))?;

    channel
        .request_pty(
            false,
            "xterm-256color",
            config.cols,
            config.rows,
            0,
            0,
            &[],
        )
        .await
        .map_err(|e| format!("申请 PTY 失败：{e}"))?;

    channel
        .request_shell(false)
        .await
        .map_err(|e| format!("启动 shell 失败：{e}"))?;

    let (input_tx, mut input_rx) = mpsc::channel::<Vec<u8>>(512);
    let (resize_tx, mut resize_rx) = mpsc::channel::<(u32, u32)>(32);
    let (close_tx, mut close_rx) = mpsc::channel::<()>(1);

    let session_id = config.session_id.clone();

    /*
     * 读写统一在一个任务里：russh 的 Channel 不是 Clone 的，
     * 用 tokio::select! 同时等待「远端输出」与「前端输入」两个来源。
     */
    {
        let session_id = session_id.clone();
        let app = app.clone();
        let mut channel = channel;

        tokio::spawn(async move {
            let mut pending: Vec<u8> = Vec::with_capacity(8192);
            let mut flush_at = tokio::time::Instant::now() + FLUSH_INTERVAL;

            loop {
                let flush_deadline = tokio::time::sleep_until(flush_at);
                tokio::pin!(flush_deadline);

                tokio::select! {
                    // 远端输出
                    msg = channel.wait() => {
                        match msg {
                            Some(ChannelMsg::Data { data }) => {
                                pending.extend_from_slice(&data);
                                // 攒够一批就立刻发，避免延迟
                                if pending.len() >= 32 * 1024 {
                                    emit_data(&app, &session_id, &mut pending);
                                    flush_at = tokio::time::Instant::now() + FLUSH_INTERVAL;
                                }
                            }
                            Some(ChannelMsg::ExtendedData { data, .. }) => {
                                pending.extend_from_slice(&data);
                            }
                            Some(ChannelMsg::Eof) | Some(ChannelMsg::Close) | None => {
                                emit_data(&app, &session_id, &mut pending);
                                let _ = app.emit(
                                    "ssh://closed",
                                    serde_json::json!({ "sessionId": session_id }),
                                );
                                break;
                            }
                            _ => {}
                        }
                    }
                    // 前端输入
                    Some(bytes) = input_rx.recv() => {
                        if channel.data(&bytes[..]).await.is_err() {
                            break;
                        }
                    }
                    // 尺寸变化
                    Some((cols, rows)) = resize_rx.recv() => {
                        let _ = channel.window_change(cols, rows, 0, 0).await;
                    }
                    // 主动关闭
                    _ = close_rx.recv() => {
                        emit_data(&app, &session_id, &mut pending);
                        let _ = channel.eof().await;
                        break;
                    }
                    // 定时把攒的数据发出去
                    _ = &mut flush_deadline => {
                        if !pending.is_empty() {
                            emit_data(&app, &session_id, &mut pending);
                        }
                        flush_at = tokio::time::Instant::now() + FLUSH_INTERVAL;
                    }
                }
            }
        });
    }

    state.sessions.lock().await.insert(
        session_id.clone(),
        SshSession {
            handle,
            input_tx,
            resize_tx,
            close_tx,
        },
    );

    Ok(ConnectResult { session_id })
}

/// 发出累积的输出。用 base64 编码避免 UTF-8 多字节被截断。
fn emit_data(app: &tauri::AppHandle, session_id: &str, pending: &mut Vec<u8>) {
    if pending.is_empty() {
        return;
    }
    use base64::Engine as _;
    let encoded = base64::engine::general_purpose::STANDARD.encode(&pending[..]);
    pending.clear();
    let _ = app.emit(
        "ssh://data",
        serde_json::json!({ "sessionId": session_id, "data": encoded }),
    );
}

// ---------------- Tauri commands ----------------

/// 测试连接（不建立持久会话）。
///
/// 用于设置页「测试」按钮：验证 TCP 可达、SSH 握手成功、凭据有效。
/// 返回各阶段耗时，方便定位是网络还是认证的问题。
#[tauri::command]
pub async fn ssh_test(config: ConnectConfig) -> Result<TestResult, String> {
    let started = std::time::Instant::now();

    let ssh_config = Arc::new(client::Config {
        inactivity_timeout: Some(Duration::from_secs(8)),
        ..Default::default()
    });

    let mut handle = client::connect(
        ssh_config,
        (config.host.as_str(), config.port),
        ClientHandler,
    )
    .await
    .map_err(|e| format!("无法连接：{e}"))?;

    let handshake_ms = started.elapsed().as_millis() as u64;

    let auth_started = std::time::Instant::now();
    let ok = match config.auth_type.as_str() {
        "password" => handle
            .authenticate_password(&config.username, config.password.as_deref().unwrap_or(""))
            .await
            .map_err(|e| format!("认证请求失败：{e}"))?
            .success(),
        "key" => {
            let pem = config
                .private_key
                .as_deref()
                .ok_or_else(|| "缺少私钥内容".to_string())?;
            let key = russh::keys::decode_secret_key(pem, config.passphrase.as_deref())
                .map_err(|e| format!("私钥解析失败：{e}"))?;
            let hash = match key.algorithm() {
                russh::keys::ssh_key::Algorithm::Rsa { .. } => {
                    Some(russh::keys::HashAlg::Sha256)
                }
                _ => None,
            };
            handle
                .authenticate_publickey(
                    &config.username,
                    PrivateKeyWithHashAlg::new(Arc::new(key), hash),
                )
                .await
                .map_err(|e| format!("认证请求失败：{e}"))?
                .success()
        }
        other => return Err(format!("不支持的认证方式：{other}")),
    };

    if !ok {
        return Err("认证失败：用户名或凭据不正确".to_string());
    }

    Ok(TestResult {
        handshake_ms,
        auth_ms: auth_started.elapsed().as_millis() as u64,
        total_ms: started.elapsed().as_millis() as u64,
    })
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TestResult {
    /// TCP 连接 + 密钥交换耗时
    pub handshake_ms: u64,
    /// 认证耗时
    pub auth_ms: u64,
    /// 总耗时
    pub total_ms: u64,
}

#[tauri::command]
pub async fn ssh_connect(
    state: tauri::State<'_, SshState>,
    app: tauri::AppHandle,
    config: ConnectConfig,
) -> Result<ConnectResult, String> {
    let registry = SshState {
        sessions: state.sessions.clone(),
    };
    connect(registry, config, app).await
}

#[tauri::command]
pub async fn ssh_write(
    state: tauri::State<'_, SshState>,
    session_id: String,
    data: String,
) -> Result<(), String> {
    use base64::Engine as _;
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(data.as_bytes())
        .map_err(|e| format!("输入编码错误：{e}"))?;

    let sessions = state.sessions.lock().await;
    let session = sessions
        .get(&session_id)
        .ok_or_else(|| "会话不存在".to_string())?;
    session
        .input_tx
        .send(bytes)
        .await
        .map_err(|_| "会话已关闭".to_string())
}

#[tauri::command]
pub async fn ssh_resize(
    state: tauri::State<'_, SshState>,
    session_id: String,
    cols: u32,
    rows: u32,
) -> Result<(), String> {
    let sessions = state.sessions.lock().await;
    if let Some(session) = sessions.get(&session_id) {
        let _ = session.resize_tx.send((cols, rows)).await;
    }
    Ok(())
}

#[tauri::command]
pub async fn ssh_disconnect(
    state: tauri::State<'_, SshState>,
    session_id: String,
) -> Result<(), String> {
    let mut sessions = state.sessions.lock().await;
    if let Some(session) = sessions.remove(&session_id) {
        let _ = session.close_tx.send(()).await;
    }
    Ok(())
}

/// 执行单条命令并收集完整输出（监控采集用）。
#[tauri::command]
pub async fn ssh_exec(
    state: tauri::State<'_, SshState>,
    session_id: String,
    command: String,
    timeout_ms: Option<u64>,
) -> Result<String, String> {
    let handle = {
        let sessions = state.sessions.lock().await;
        let session = sessions
            .get(&session_id)
            .ok_or_else(|| "会话不存在".to_string())?;
        session.handle.clone()
    };

    let mut channel = handle
        .channel_open_session()
        .await
        .map_err(|e| format!("打开执行通道失败：{e}"))?;

    channel
        .exec(true, command.as_bytes())
        .await
        .map_err(|e| format!("执行失败：{e}"))?;

    let mut out: Vec<u8> = Vec::new();
    let deadline = tokio::time::Instant::now()
        + Duration::from_millis(timeout_ms.unwrap_or(15_000));

    loop {
        tokio::select! {
            msg = channel.wait() => {
                match msg {
                    Some(ChannelMsg::Data { data }) => out.extend_from_slice(&data),
                    Some(ChannelMsg::ExtendedData { data, .. }) => out.extend_from_slice(&data),
                    Some(ChannelMsg::ExitStatus { .. }) | Some(ChannelMsg::Eof) | Some(ChannelMsg::Close) | None => break,
                    _ => {}
                }
            }
            _ = tokio::time::sleep_until(deadline) => {
                return Err("命令执行超时".to_string());
            }
        }
    }

    Ok(String::from_utf8_lossy(&out).into_owned())
}