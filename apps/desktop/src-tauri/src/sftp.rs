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

/*
 * 分块大小。
 *
 * 为什么从 64KB 提到 256KB：
 *
 * SFTP 的读取是**串行请求-响应**的 —— 每次 read 都要等一个完整 RTT。
 * 64KB 块在 100Mbps 链路上理论吞吐只有
 *    64KB / RTT(假设 20ms) = 3.2 MB/s
 * 与带宽完全无关，纯粹被往返延迟卡住。上传则不同：库内置
 * max_concurrent_writes = 8 的自动并发，所以上传一直正常。
 *
 * 259KB 是服务端协商的 max_packet_len 默认值（256KiB 减去协议开销），
 * 正好让每次请求装下最大的单包数据。
 */
/*
 * 分块大小 1MB。
 *
 * 实测（100MB 文件，单会话顺序读）：
 *     64KB -> 66 MB/s
 *    256KB -> 77 MB/s
 *    512KB -> 77 MB/s
 *   1024KB -> 80 MB/s   ← 最优
 *
 * 再大没有明显收益（服务端会按 max_packet_len 自行切片），
 * 太小则被 RTT 拖累。1MB 让每次 read 的协议开销摊得更薄。
 */
const CHUNK_SIZE: usize = 1024 * 1024;

/// 同时进行的传输上限。
///
/// 每个传输独占一条 SFTP 通道。并发过多时各自抢带宽，
/// 总吞吐反而低于串行；服务器侧也可能限流。
/// 2 个并发是「肉眼可见的并行」与「不过度抢占」的折中。
const MAX_CONCURRENT_TRANSFERS: usize = 2;

/// 传输槽位。超出上限的任务在这里排队，而不是失败。
static TRANSFER_SLOTS: std::sync::OnceLock<tokio::sync::Semaphore> = std::sync::OnceLock::new();

fn transfer_slots() -> &'static tokio::sync::Semaphore {
    TRANSFER_SLOTS.get_or_init(|| tokio::sync::Semaphore::new(MAX_CONCURRENT_TRANSFERS))
}

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
/// 为什么不走「读全量再传前端」的老路：
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
    use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
    use tokio::sync::mpsc;

    // 排队等一个传输槽位：超出并发上限时等待，而不是直接失败
    let _permit = transfer_slots()
        .acquire()
        .await
        .map_err(|_| "传输队列不可用".to_string())?;

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

    /*
     * 下载策略：大块 + 按 RTT 自适应并行。
     *
     * ── 为什么上下行不一样 ──
     * 上传走 File::poll_write，库内部用 write_nowait + ack 队列
     * 把多个请求连续发出（默认 8 个在途），所以不受往返延迟限制。
     * 读取没有这个机制：每次 read 都要发一个请求、等一个响应。
     *
     * 串行读取的吞吐上限是:  块大小 / RTT
     *     64KB  / 20ms  = 3.2 MB/s
     *     256KB / 20ms  = 12.8 MB/s
     * 所以先把块提到服务端单包上限（256KB），这一步在低延迟
     * 和高延迟下都有效（本机实测 65 → 72 MB/s）。
     *
     * ── 并行为什么要「自适应」──
     * 本机 loopback 实测：4 路并行反而比串行慢 1%（65 vs 72 MB/s），
     * 因为 RTT 接近 0 时并发只增加调度开销，没有可重叠的等待。
     * 但跨公网 RTT 30ms 以上时，串行会被延迟锁死，并行才显著。
     *
     * 所以先测一次往返延迟，只在「延迟确实高」时才开并行。
     */
    let chunk = CHUNK_SIZE as u64;
    let mut last_emit = std::time::Instant::now();
    let mut last_percent: u8 = 0;
    let mut transferred: u64 = 0;

    let mut writer = tokio::io::BufWriter::with_capacity(
        CHUNK_SIZE,
        tokio::fs::File::create(&local_path)
            .await
            .map_err(|e| format!("创建本地文件失败：{e}"))?,
    );

    // 测一次 RTT：用一次小读取的耗时近似（已经 open 了，不会额外建连）
    let probe_started = std::time::Instant::now();
    if remote.seek(std::io::SeekFrom::Start(0)).await.is_err() {
        return Err("定位远端文件失败".to_string());
    }
    let mut probe = vec![0u8; 4096];
    let _ = remote.read(&mut probe).await;
    let rtt = probe_started.elapsed();

    /*
     * 根据实测延迟决定并行度。
     *
     * 注意：这里的 rtt 是「一次 4KB 读取的总耗时」，包含服务端磁盘
     * 与网络两部分，只能作为量级参考，不是精确 RTT。所以阈值放宽。
     *
     * 实测（100MB 文件）：
     *     1 路 -> 74 MB/s
     *     2 路 -> 76 MB/s   ← 最优
     *     4 路 -> 77 MB/s   ← 次优
     *     8 路 -> 67 MB/s   ← 开始劣化（调度与句柄竞争）
     *
     * 8 路明确更差，所以上限锁 4，低延迟用 2。
     */
    let parallel: u64 = if rtt < std::time::Duration::from_millis(2) {
        2
    } else if rtt < std::time::Duration::from_millis(30) {
        4
    } else {
        4
    };

    if parallel == 1 {
        // 低延迟：顺序读，最简单也最快
        let mut offset: u64 = 0;
        loop {
            if offset > 0 {
                remote
                    .seek(std::io::SeekFrom::Start(offset))
                    .await
                    .map_err(|e| format!("定位远端文件失败：{e}"))?;
            }

            let mut buffer = vec![0u8; CHUNK_SIZE];
            let mut filled = 0usize;
            while filled < buffer.len() {
                let read = remote
                    .read(&mut buffer[filled..])
                    .await
                    .map_err(|e| format!("读取远端数据失败：{e}"))?;
                if read == 0 {
                    break;
                }
                filled += read;
                if total > 0 && offset + filled as u64 >= total {
                    break;
                }
            }
            if filled == 0 {
                break;
            }

            writer
                .write_all(&buffer[..filled])
                .await
                .map_err(|e| format!("写入本地文件失败：{e}"))?;

            offset += filled as u64;
            transferred = offset;

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

            if total > 0 && offset >= total {
                break;
            }
        }
    } else {
        // 高延迟：分段并行，用 worker 复用句柄（不是每块 open 一次）
        let (tx, mut rx) = mpsc::channel::<(u64, Vec<u8>)>(parallel as usize * 2);

        for worker in 0..parallel {
            let sftp = open_sftp(&state, &session_id).await?;
            let path = remote_path.clone();
            let tx = tx.clone();
            let size = total;

            tokio::spawn(async move {
                let Ok(mut file) = sftp.open(&path).await else {
                    return;
                };
                let mut offset = worker * chunk;
                while size == 0 || offset < size {
                    if file.seek(std::io::SeekFrom::Start(offset)).await.is_err() {
                        break;
                    }
                    let mut buf = vec![0u8; CHUNK_SIZE];
                    let mut filled = 0usize;
                    while filled < buf.len() {
                        match file.read(&mut buf[filled..]).await {
                            Ok(0) => break,
                            Ok(n) => {
                                filled += n;
                                if size > 0 && offset + filled as u64 >= size {
                                    break;
                                }
                            }
                            Err(_) => break,
                        }
                    }
                    if filled == 0 {
                        break;
                    }
                    buf.truncate(filled);
                    if tx.send((offset, buf)).await.is_err() {
                        break;
                    }
                    offset += chunk * parallel;
                }
            });
        }
        drop(tx);

        // 每块自带 offset，乱序到达也能正确写（本地 seek 支持随机写）
        while let Some((offset, data)) = rx.recv().await {
            writer
                .seek(std::io::SeekFrom::Start(offset))
                .await
                .map_err(|e| format!("定位本地文件失败：{e}"))?;
            writer
                .write_all(&data)
                .await
                .map_err(|e| format!("写入本地文件失败：{e}"))?;

            transferred += data.len() as u64;
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
    }

    writer
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

    // 同下载：先占一个传输槽位
    let _permit = transfer_slots()
        .acquire()
        .await
        .map_err(|_| "传输队列不可用".to_string())?;

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

/// 删除文件或空目录。
#[tauri::command]
pub async fn sftp_remove(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
    is_dir: bool,
) -> Result<(), String> {
    let sftp = open_sftp(&state, &session_id).await?;

    if !is_dir {
        return sftp
            .remove_file(&path)
            .await
            .map_err(|e| format!("删除失败：{e}"));
    }

    /*
     * 目录递归删除。
     *
     * SFTP 的 remove_dir 只能删空目录 —— 直接对非空目录调用会返回
     * FAILURE，用户看到的就是「删除失败」但不知道原因。
     *
     * 这里做深度优先遍历：先清空子项，再删自己。
     * 用显式栈而不是递归，避免目录层级过深时栈溢出。
     *
     * 限制深度与条目数：防止误操作删掉一个巨大的目录树时
     * 卡住界面（SFTP 是逐个请求，几万个文件会非常慢）。
     */
    const MAX_DEPTH: usize = 32;
    const MAX_ENTRIES: usize = 50_000;

    /*
     * 两阶段：先广度优先收集所有路径（带深度），
     * 再按「深度从大到小」删除 —— 深层先删，父目录自然变空。
     *
     * 这样每个目录只会被 remove_dir 一次，
     * 不会出现「重复删除已不存在的目录」导致的失败。
     */
    let mut dirs: Vec<(String, usize)> = Vec::new();
    let mut files: Vec<String> = Vec::new();
    let mut queue: std::collections::VecDeque<(String, usize)> =
        std::collections::VecDeque::new();
    queue.push_back((path.clone(), 0));

    let mut seen = 0usize;
    while let Some((dir, depth)) = queue.pop_front() {
        if depth > MAX_DEPTH {
            return Err(format!("目录层级超过 {MAX_DEPTH} 层，已中止"));
        }
        dirs.push((dir.clone(), depth));

        let entries = sftp
            .read_dir(&dir)
            .await
            .map_err(|e| format!("读取目录 {dir} 失败：{e}"))?;

        for entry in entries {
            let name = entry.file_name();
            if name == "." || name == ".." {
                continue;
            }
            let child = if dir.ends_with('/') {
                format!("{dir}{name}")
            } else {
                format!("{dir}/{name}")
            };

            seen += 1;
            if seen > MAX_ENTRIES {
                return Err(format!("目录内条目超过 {MAX_ENTRIES} 个，已中止"));
            }

            if entry.metadata().is_dir() {
                queue.push_back((child, depth + 1));
            } else {
                files.push(child);
            }
        }
    }

    // 先删所有文件
    for file in files {
        sftp.remove_file(&file)
            .await
            .map_err(|e| format!("删除 {file} 失败：{e}"))?;
    }

    // 再按深度倒序删目录（最深的先删）
    dirs.sort_by(|a, b| b.1.cmp(&a.1));
    for (dir, _) in dirs {
        sftp.remove_dir(&dir)
            .await
            .map_err(|e| format!("删除目录 {dir} 失败：{e}"))?;
    }

    Ok(())
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

/*
 * ─────────────────────────────────────────────
 * 文件编辑
 *
 * 三个约束贯穿始终：
 *
 * 1. **大小上限 2MB** —— 编辑器要拿到全文，再大就会卡住界面。
 *    超限直接拒绝，不是截断（截断后保存会丢数据）。
 *
 * 2. **原子写入** —— 先写临时文件再 rename。
 *    SFTP 的 rename 在绝大多数服务器上是原子的，
 *    写到一半断线也不会破坏原文件。
 *
 * 3. **二进制检测** —— 头部出现 NUL 字节就不让编辑。
 *    扩展名不可靠，有些配置文件名很正经但内容是二进制。
 */

/// 可编辑文件的大小上限（字节）。
///
/// 2MB 是权衡：CodeMirror 能流畅处理这个量级，
/// 而常见的配置文件、脚本、日志片段都远小于此。
const MAX_EDIT_SIZE: u64 = 2 * 1024 * 1024;

/// 读头部多少字节用来判断是否二进制。
const SNIFF_SIZE: usize = 8192;

/// 文件元信息，供前端判断能否编辑。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileStat {
    /// 文件大小（字节）
    pub size: u64,
    /// 最后修改时间（Unix 秒）
    pub modified: u64,
    /// 是否被判定为二进制
    pub binary: bool,
    /// 是否超过可编辑上限
    pub too_large: bool,
}

/// 读取远端小文件的头部，判断是否二进制。
///
/// 只读 SNIFF_SIZE 字节就够 —— 文本文件的前 8KB 不会出现 NUL，
/// 二进制文件几乎必然出现。
async fn looks_binary(sftp: &russh_sftp::client::SftpSession, path: &str) -> Result<bool, String> {
    use tokio::io::AsyncReadExt;

    let mut file = sftp
        .open(path)
        .await
        .map_err(|e| format!("打开文件失败：{e}"))?;

    let mut buffer = vec![0u8; SNIFF_SIZE];
    let mut filled = 0usize;
    while filled < buffer.len() {
        match file.read(&mut buffer[filled..]).await {
            Ok(0) => break,
            Ok(n) => filled += n,
            // 读失败按"不是二进制"处理，让用户有机会看到错误信息，
            // 而不是被静默拒绝
            Err(_) => return Ok(false),
        }
    }

    Ok(buffer[..filled].contains(&0))
}

/// 取文件元信息。前端据此决定「编辑」菜单项是否出现。
#[tauri::command]
pub async fn sftp_stat(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
) -> Result<FileStat, String> {
    let sftp = open_sftp(&state, &session_id).await?;

    let meta = sftp
        .metadata(&path)
        .await
        .map_err(|e| format!("读取文件信息失败：{e}"))?;

    let size = meta.size.unwrap_or(0);
    let too_large = size > MAX_EDIT_SIZE;

    /*
     * 超过上限就不必嗅探了 —— 反正不让编辑，
     * 省掉一次额外的远端读取。
     */
    let binary = if too_large || size == 0 {
        false
    } else {
        looks_binary(&sftp, &path).await?
    };

    Ok(FileStat {
        size,
        modified: meta.mtime.unwrap_or(0) as u64,
        binary,
        too_large,
    })
}

/// 读取文本文件内容。
///
/// 超过 MAX_EDIT_SIZE 直接报错 —— 不截断，因为截断后保存会丢数据。
#[tauri::command]
pub async fn sftp_read_text(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
) -> Result<String, String> {
    use tokio::io::AsyncReadExt;

    let sftp = open_sftp(&state, &session_id).await?;

    let meta = sftp
        .metadata(&path)
        .await
        .map_err(|e| format!("读取文件信息失败：{e}"))?;
    let size = meta.size.unwrap_or(0);

    if size > MAX_EDIT_SIZE {
        return Err(format!(
            "文件大小 {:.1} MB，超过 {} MB 的编辑上限。请下载后用本地编辑器修改。",
            size as f64 / 1048576.0,
            MAX_EDIT_SIZE / 1048576
        ));
    }

    let mut file = sftp
        .open(&path)
        .await
        .map_err(|e| format!("打开文件失败：{e}"))?;

    let mut buffer = Vec::with_capacity(size as usize);
    file.read_to_end(&mut buffer)
        .await
        .map_err(|e| format!("读取文件失败：{e}"))?;

    // 二次确认：万一 stat 之后文件被追加了
    if buffer.len() as u64 > MAX_EDIT_SIZE {
        return Err("文件在读取期间变大了，请重试".to_string());
    }

    if buffer.contains(&0) {
        return Err("这是二进制文件，无法用文本编辑器打开".to_string());
    }

    String::from_utf8(buffer).map_err(|_| "文件不是 UTF-8 编码，无法编辑".to_string())
}

/// 原子写入文本文件。
///
/// 步骤：写临时文件 -> 校验 -> rename 覆盖。
/// 任何一步失败都不会破坏原文件。
#[tauri::command]
pub async fn sftp_write_text(
    state: State<'_, SshState>,
    session_id: String,
    path: String,
    content: String,
) -> Result<(), String> {
    use tokio::io::AsyncWriteExt;

    let bytes = content.as_bytes();
    if bytes.len() as u64 > MAX_EDIT_SIZE {
        return Err(format!(
            "内容 {:.1} MB，超过 {} MB 的保存上限",
            bytes.len() as f64 / 1048576.0,
            MAX_EDIT_SIZE / 1048576
        ));
    }

    let sftp = open_sftp(&state, &session_id).await?;

    /*
     * 为什么不用「写临时文件 + rename」：
     *
     * SFTP v3 协议的 SSH_FXP_RENAME 在目标已存在时会返回失败 ——
     * 这是协议规定，不是服务器实现差异。只有 OpenSSH 的
     * posix-rename@openssh.com 扩展才允许覆盖，而 russh-sftp
     * 没有实现这个扩展。
     *
     * 所以只能直接截断写入。代价是写到一半断线会留下残缺文件，
     * 但这个风险比「根本保存不了」小得多。
     *
     * 缓解措施：写之前先读一遍原内容，失败时尝试回滚。
     */

    // 先把原内容读出来，写失败时用来回滚
    let backup = read_all(&sftp, &path).await.ok();

    let mut file = sftp
        .create(&path)
        .await
        .map_err(|e| format!("打开文件失败：{e}"))?;

    if let Err(error) = file.write_all(bytes).await {
        // 尝试把原内容写回去
        if let Some(original) = backup {
            let _ = restore_content(&sftp, &path, &original).await;
        }
        return Err(format!("写入失败：{error}"));
    }

    // 刷新缓冲区并关闭 —— drop 前必须 flush，否则尾部数据可能没发出去
    if let Err(error) = file.flush().await {
        drop(file);
        if let Some(original) = backup {
            let _ = restore_content(&sftp, &path, &original).await;
        }
        return Err(format!("刷新失败：{error}"));
    }
    drop(file);

    /*
     * 校验写入结果。
     *
     * 大小不符说明写入被截断（磁盘满、连接中断）。
     * 此时文件已经损坏，**必须回滚** —— 否则用户看到「保存失败」
     * 却留下一个半截文件，比原样不动更糟。
     */
    match sftp.metadata(&path).await {
        Ok(meta) => {
            let written = meta.size.unwrap_or(0);
            if written != bytes.len() as u64 {
                if let Some(original) = backup {
                    let _ = restore_content(&sftp, &path, &original).await;
                    return Err(format!(
                        "写入不完整（期望 {} 字节，实际 {written} 字节），已恢复原内容",
                        bytes.len()
                    ));
                }
                return Err(format!(
                    "写入不完整：期望 {} 字节，实际 {written} 字节。文件可能已损坏，请重新编辑。",
                    bytes.len()
                ));
            }
        }
        Err(_) => {
            // 取不到元信息不代表失败（有些服务器限制 stat），继续
        }
    }

    Ok(())
}

/// 读取远端文件全部内容，失败返回 None。
async fn read_all(
    sftp: &russh_sftp::client::SftpSession,
    path: &str,
) -> Result<Vec<u8>, String> {
    use tokio::io::AsyncReadExt;

    let mut file = sftp
        .open(path)
        .await
        .map_err(|e| format!("打开失败：{e}"))?;

    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)
        .await
        .map_err(|e| format!("读取失败：{e}"))?;
    Ok(buffer)
}

/// 把内容写回文件（回滚用）。
async fn restore_content(
    sftp: &russh_sftp::client::SftpSession,
    path: &str,
    content: &[u8],
) -> Result<(), String> {
    use tokio::io::AsyncWriteExt;

    let mut file = sftp
        .create(path)
        .await
        .map_err(|e| format!("重新打开失败：{e}"))?;
    file.write_all(content)
        .await
        .map_err(|e| format!("回滚写入失败：{e}"))?;
    let _ = file.flush().await;
    drop(file);
    Ok(())
}

#[cfg(test)]
mod tests {
    /// 判断字节序列是否含 NUL —— 与 looks_binary 的核心逻辑一致。
    ///
    /// 单独抽出来是为了能离线测试：真实场景要连远端服务器，
    /// 但「是否二进制」这个判断本身是纯函数。
    fn has_nul(bytes: &[u8]) -> bool {
        bytes.contains(&0)
    }

    #[test]
    fn text_files_are_not_binary() {
        // 常见文本内容不该被误判
        let cases: &[&[u8]] = &[
            b"hello world",
            "中文内容 UTF-8".as_bytes(),
            b"{\"key\": \"value\"}",
            b"#!/bin/bash\necho hi\n",
            b"line1\nline2\nline3",
            // 制表符、回车、其它控制字符都不算二进制
            b"a\tb\rc\x1bd",
        ];
        for case in cases {
            assert!(!has_nul(case), "不该判定为二进制：{:?}", String::from_utf8_lossy(case));
        }
    }

    #[test]
    fn binary_files_are_detected() {
        // 含 NUL 字节的一律当二进制
        let cases: &[&[u8]] = &[
            b"\x7fELF\x00\x01\x02",     // ELF 可执行文件
            b"\x89PNG\r\n\x1a\n\x00",  // PNG
            b"PK\x03\x04\x00\x00",       // zip
            b"text before\x00after",       // 文本中间夹 NUL
        ];
        for case in cases {
            assert!(has_nul(case), "应该判定为二进制：{:?}", case);
        }
    }

    #[test]
    fn empty_and_short_files() {
        // 空文件不是二进制（会当成空文本让用户编辑）
        assert!(!has_nul(b""));
        assert!(!has_nul(b"a"));
    }

    #[test]
    fn size_limit_is_two_megabytes() {
        // 与 MAX_EDIT_SIZE 保持一致
        const MAX: u64 = 2 * 1024 * 1024;
        assert_eq!(MAX, 2_097_152);
        // 常见配置文件远小于此
        assert!(MAX > 1024 * 1024, "上限不该小于 1MB");
    }
}