//! SFTP 文件管理。
//!
//! 复用 SSH 会话：从 registry 取 handle，每次操作开一个 sftp channel。
//! 列表 / 读写都是请求-响应语义，不需要长连接状态。

use serde::Serialize;
use tauri::State;

use crate::ssh::SshState;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SftpEntry {
    pub name: String,
    /// 完整路径
    pub path: String,
    pub is_dir: bool,
    /// 文件大小（目录为 0）
    pub size: u64,
    /// 修改时间（Unix 秒）
    pub modified: u64,
    /// 权限（八进制字符串，如 "644"）
    pub mode: String,
}

/// 打开一个 sftp 子系统通道。
async fn open_sftp(
    state: &State<'_, SshState>,
    session_id: &str,
) -> Result<russh_sftp::client::SftpSession, String> {
    let handle = {
        let sessions = state.sessions.lock().await;
        let session = sessions
            .get(session_id)
            .ok_or_else(|| "会话不存在".to_string())?;
        session.handle.clone()
    };

    let channel = handle
        .channel_open_session()
        .await
        .map_err(|e| format!("打开 SFTP 通道失败：{e}"))?;

    channel
        .request_subsystem(true, "sftp")
        .await
        .map_err(|e| format!("启动 SFTP 子系统失败：{e}"))?;

    russh_sftp::client::SftpSession::new(channel.into_stream())
        .await
        .map_err(|e| format!("初始化 SFTP 失败：{e}"))
}

/// 分块大小：64KB。足够小以更新进度，足够大以保证吞吐。
const CHUNK_SIZE: usize = 64 * 1024;

/// 进度事件的节流间隔。
///
/// 64KB 一块意味着 1GB 文件会产生 16000 次 emit ——
/// 每次 emit 都要跨 IPC 序列化 + 唤醒渲染层，
/// 会明显拖慢传输并造成界面卡顿（与终端输出洪泛是同类问题）。
/// 按 100ms 节流后，1GB 传输只剩约 10-20 次进度事件。
const PROGRESS_INTERVAL: std::time::Duration = std::time::Duration::from_millis(100);

/// 判断是否该发下一次进度。
///
/// 同时兼顾时间与百分比：时间到了就发（保证慢速网络也有反馈），
/// 进度满 100% 时必发（让 UI 能收到终态）。
fn should_emit(last: &mut std::time::Instant, percent: u8, last_percent: &mut u8) -> bool {
    let now = std::time::Instant::now();
    if percent >= 100 && *last_percent < 100 {
        *last = now;
        *last_percent = percent;
        return true;
    }
    if now.duration_since(*last) >= PROGRESS_INTERVAL {
        *last = now;
        *last_percent = percent;
        return true;
    }
    false
}

/// 下载到本地文件（Rust 直连，不经过 JS）。
///
/// 为什么不复用 `sftp_read` + JS 保存：
/// base64 编码一个 100MB 文件会让渲染进程主线程卡死好几秒，
/// 而且字符串要跨 IPC 传两遍。这里直接在 Rust 里读远端、写本地，
/// 前端只收进度事件。
#[tauri::command]
pub async fn sftp_download(
    app: tauri::AppHandle,
    state: State<'_, SshState>,
    session_id: String,
    remote_path: String,
    local_path: String,
    task_id: String,
) -> Result<(), String> {
    use tauri::Emitter;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let sftp = open_sftp(&state, &session_id).await?;

    let mut remote = sftp
        .open(&remote_path)
        .await
        .map_err(|e| format!("打开远端文件失败：{e}"))?;

    let total = remote
        .metadata()
        .await
        .map(|meta| meta.size.unwrap_or(0))
        .unwrap_or(0);

    let mut local = tokio::fs::File::create(&local_path)
        .await
        .map_err(|e| format!("创建本地文件失败：{e}"))?;

    let mut buffer = vec![0u8; CHUNK_SIZE];
    let mut transferred: u64 = 0;
    let mut last_emit = std::time::Instant::now();
    let mut last_percent: u8 = 0;

    loop {
        let read = remote
            .read(&mut buffer)
            .await
            .map_err(|e| format!("读取远端数据失败：{e}"))?;
        if read == 0 {
            break;
        }
        local
            .write_all(&buffer[..read])
            .await
            .map_err(|e| format!("写入本地文件失败：{e}"))?;

        transferred += read as u64;
        let percent = if total > 0 {
            ((transferred as f64 / total as f64) * 100.0).min(100.0) as u8
        } else {
            0
        };

        // 节流：不是每块都发事件
        if should_emit(&mut last_emit, percent, &mut last_percent) {
            let _ = app.emit(
                "sftp://progress",
                serde_json::json!({
                    "taskId": task_id,
                    "transferred": transferred,
                    "total": total,
                    "percent": percent
                }),
            );
        }
    }

    local
        .flush()
        .await
        .map_err(|e| format!("保存失败：{e}"))?;
    Ok(())
}

/// 从本地文件上传（Rust 直连）。
#[tauri::command]
pub async fn sftp_upload(
    app: tauri::AppHandle,
    state: State<'_, SshState>,
    session_id: String,
    local_path: String,
    remote_path: String,
    task_id: String,
) -> Result<(), String> {
    use tauri::Emitter;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let total = tokio::fs::metadata(&local_path)
        .await
        .map(|meta| meta.len())
        .unwrap_or(0);

    let mut local = tokio::fs::File::open(&local_path)
        .await
        .map_err(|e| format!("打开本地文件失败：{e}"))?;

    let sftp = open_sftp(&state, &session_id).await?;
    let mut remote = sftp
        .create(&remote_path)
        .await
        .map_err(|e| format!("创建远端文件失败：{e}"))?;

    let mut buffer = vec![0u8; CHUNK_SIZE];
    let mut transferred: u64 = 0;
    let mut last_emit = std::time::Instant::now();
    let mut last_percent: u8 = 0;

    loop {
        let read = local
            .read(&mut buffer)
            .await
            .map_err(|e| format!("读取本地文件失败：{e}"))?;
        if read == 0 {
            break;
        }
        remote
            .write_all(&buffer[..read])
            .await
            .map_err(|e| format!("写入远端失败：{e}"))?;

        transferred += read as u64;
        let percent = if total > 0 {
            ((transferred as f64 / total as f64) * 100.0).min(100.0) as u8
        } else {
            0
        };

        if should_emit(&mut last_emit, percent, &mut last_percent) {
            let _ = app.emit(
                "sftp://progress",
                serde_json::json!({
                    "taskId": task_id,
                    "transferred": transferred,
                    "total": total,
                    "percent": percent
                }),
            );
        }
    }

    remote
        .flush()
        .await
        .map_err(|e| format!("刷盘失败：{e}"))?;
    let _ = remote.shutdown().await;
    Ok(())
}

/// 列出目录内容。
#[tauri::command]
pub async fn sftp_list(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
) -> Result<Vec<SftpEntry>, String> {
    let sftp = open_sftp(&state, &session_id).await?;

    let dir = if path.is_empty() { "." } else { path.as_str() };
    let entries = sftp
        .read_dir(dir)
        .await
        .map_err(|e| format!("读取目录失败：{e}"))?;

    let mut result: Vec<SftpEntry> = Vec::new();
    for entry in entries {
        let name = entry.file_name();
        if name == "." || name == ".." {
            continue;
        }
        let attrs = entry.metadata();
        let mode = attrs.permissions.unwrap_or(0);
        let is_dir = attrs.is_dir();

        result.push(SftpEntry {
            path: if dir == "." {
                name.clone()
            } else {
                format!("{}/{}", dir.trim_end_matches('/'), name)
            },
            name,
            is_dir,
            size: attrs.size.unwrap_or(0),
            modified: attrs.mtime.unwrap_or(0) as u64,
            mode: format!("{:o}", mode & 0o777),
        });
    }

    // 目录在前，然后按名称排序
    result.sort_by(|a, b| match (a.is_dir, b.is_dir) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
    });

    Ok(result)
}

/// 读取文件内容（返回 base64，避免二进制损坏）。
#[tauri::command]
pub async fn sftp_read(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
) -> Result<String, String> {
    use base64::Engine as _;
    use tokio::io::AsyncReadExt;

    let sftp = open_sftp(&state, &session_id).await?;
    let mut file = sftp
        .open(&path)
        .await
        .map_err(|e| format!("打开文件失败：{e}"))?;

    let mut buf = Vec::new();
    file.read_to_end(&mut buf)
        .await
        .map_err(|e| format!("读取失败：{e}"))?;

    Ok(base64::engine::general_purpose::STANDARD.encode(&buf))
}

/// 写入文件（内容为 base64）。
#[tauri::command]
pub async fn sftp_write(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
    content: String,
) -> Result<(), String> {
    use base64::Engine as _;
    use tokio::io::AsyncWriteExt;

    let bytes = base64::engine::general_purpose::STANDARD
        .decode(content.as_bytes())
        .map_err(|e| format!("内容编码错误：{e}"))?;

    let sftp = open_sftp(&state, &session_id).await?;
    let mut file = sftp
        .create(&path)
        .await
        .map_err(|e| format!("创建文件失败：{e}"))?;

    file.write_all(&bytes)
        .await
        .map_err(|e| format!("写入失败：{e}"))?;
    file.flush().await.map_err(|e| format!("刷盘失败：{e}"))?;
    let _ = file.shutdown().await;

    Ok(())
}

/// 删除文件或空目录。
#[tauri::command]
pub async fn sftp_remove(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
    is_dir: bool,
) -> Result<(), String> {
    let sftp = open_sftp(&state, &session_id).await?;
    let result = if is_dir {
        sftp.remove_dir(&path).await
    } else {
        sftp.remove_file(&path).await
    };
    result.map_err(|e| format!("删除失败：{e}"))
}

/// 创建目录。
#[tauri::command]
pub async fn sftp_mkdir(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
) -> Result<(), String> {
    let sftp = open_sftp(&state, &session_id).await?;
    sftp.create_dir(&path)
        .await
        .map_err(|e| format!("创建目录失败：{e}"))
}

/// 修改权限。
#[tauri::command]
pub async fn sftp_chmod(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
    mode: u32,
) -> Result<(), String> {
    let sftp = open_sftp(&state, &session_id).await?;
    sftp.set_metadata(
        &path,
        russh_sftp::protocol::FileAttributes {
            permissions: Some(mode & 0o7777),
            ..Default::default()
        },
    )
    .await
    .map_err(|e| format!("修改权限失败：{e}"))
}

/// 重命名 / 移动。
#[tauri::command]
pub async fn sftp_rename(
    state: State<'_, SshState>,
    session_id: String,
    from: String,
    to: String,
) -> Result<(), String> {
    let sftp = open_sftp(&state, &session_id).await?;
    sftp.rename(&from, &to)
        .await
        .map_err(|e| format!("重命名失败：{e}"))
}