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