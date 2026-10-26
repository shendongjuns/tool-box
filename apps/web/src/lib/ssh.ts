import { isTauriRuntime } from "./platform";

/**
 * SSH / SFTP 桥接层。
 *
 * 所有网络 I/O 都在 Rust 侧完成（WebView 无法建立原始 TCP 连接）。
 * 这里只负责 invoke 调用与事件订阅。
 *
 * 网页端不支持 SSH —— 会直接抛出可读错误。
 */

export interface ConnectConfig {
  sessionId: string;
  host: string;
  port: number;
  username: string;
  authType: "password" | "key";
  password?: string;
  privateKey?: string;
  passphrase?: string;
  cols: number;
  rows: number;
}

export interface SftpEntry {
  name: string;
  path: string;
  isDir: boolean;
  size: number;
  modified: number;
  mode: string;
}

type Invoke = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;

let invokeRef: Invoke | null = null;

async function getInvoke(): Promise<Invoke> {
  if (!isTauriRuntime()) {
    throw new Error("SSH 仅在桌面端可用（浏览器无法建立 TCP 连接）");
  }
  if (invokeRef) return invokeRef;
  const core = (await import("@tauri-apps/api/core")) as unknown as { invoke: Invoke };
  invokeRef = core.invoke;
  return invokeRef;
}

/** 建立 SSH 连接并打开交互式 shell。 */
export async function sshConnect(config: ConnectConfig): Promise<void> {
  const invoke = await getInvoke();
  await invoke("ssh_connect", { config });
}

/** 写入终端输入（base64 编码的字节）。 */
export async function sshWrite(sessionId: string, data: string): Promise<void> {
  const invoke = await getInvoke();
  await invoke("ssh_write", { sessionId, data });
}

/** 调整远端 PTY 尺寸。 */
export async function sshResize(sessionId: string, cols: number, rows: number): Promise<void> {
  const invoke = await getInvoke();
  await invoke("ssh_resize", { sessionId, cols, rows });
}

/** 关闭会话。 */
export async function sshDisconnect(sessionId: string): Promise<void> {
  const invoke = await getInvoke();
  await invoke("ssh_disconnect", { sessionId });
}

/** 执行单条命令并取回完整输出（监控采集用）。 */
export async function sshExec(
  sessionId: string,
  command: string,
  timeoutMs = 15_000,
): Promise<string> {
  const invoke = await getInvoke();
  return invoke<string>("ssh_exec", { sessionId, command, timeoutMs });
}

/** 订阅终端输出与关闭事件。返回取消订阅函数。 */
export async function subscribeSsh(
  handlers: {
    onData: (sessionId: string, bytes: Uint8Array) => void;
    onClosed: (sessionId: string) => void;
  },
): Promise<() => void> {
  if (!isTauriRuntime()) return () => {};

  const { listen } = await import("@tauri-apps/api/event");

  const unlistenData = await listen<{ sessionId: string; data: string }>(
    "ssh://data",
    (event) => {
      const binary = atob(event.payload.data);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
      handlers.onData(event.payload.sessionId, bytes);
    },
  );

  const unlistenClosed = await listen<{ sessionId: string }>("ssh://closed", (event) => {
    handlers.onClosed(event.payload.sessionId);
  });

  return () => {
    unlistenData();
    unlistenClosed();
  };
}

// ---------------- SFTP ----------------

export async function sftpList(sessionId: string, path: string): Promise<SftpEntry[]> {
  const invoke = await getInvoke();
  return invoke<SftpEntry[]>("sftp_list", { sessionId, path });
}

export async function sftpRead(sessionId: string, path: string): Promise<string> {
  const invoke = await getInvoke();
  return invoke<string>("sftp_read", { sessionId, path });
}

export async function sftpWrite(
  sessionId: string,
  path: string,
  contentBase64: string,
): Promise<void> {
  const invoke = await getInvoke();
  await invoke("sftp_write", { sessionId, path, content: contentBase64 });
}

export async function sftpRemove(
  sessionId: string,
  path: string,
  isDir: boolean,
): Promise<void> {
  const invoke = await getInvoke();
  await invoke("sftp_remove", { sessionId, path, isDir });
}

export async function sftpMkdir(sessionId: string, path: string): Promise<void> {
  const invoke = await getInvoke();
  await invoke("sftp_mkdir", { sessionId, path });
}

export async function sftpRename(sessionId: string, from: string, to: string): Promise<void> {
  const invoke = await getInvoke();
  await invoke("sftp_rename", { sessionId, from, to });
}

/** 修改权限（八进制，如 0o644）。 */
export async function sftpChmod(sessionId: string, path: string, mode: number): Promise<void> {
  const invoke = await getInvoke();
  await invoke("sftp_chmod", { sessionId, path, mode });
}

/** 取当前工作目录（绝对路径），用于文件浏览器的起始路径。 */
export async function remoteHomeDir(sessionId: string): Promise<string> {
  const { sshExec } = await import("./ssh");
  try {
    const raw = await sshExec(sessionId, "pwd 2>/dev/null || echo /", 5000);
    const line = raw.trim().split("\n")[0] ?? "/";
    return line.startsWith("/") ? line : "/";
  } catch {
    return "/";
  }
}

/**
 * 下载远端文件到本地路径（Rust 直连，带进度事件）。
 *
 * 不用 sftpRead + base64：大文件编码会卡死渲染进程。
 */
export async function sftpDownload(
  sessionId: string,
  remotePath: string,
  localPath: string,
  taskId: string,
): Promise<void> {
  const invoke = await getInvoke();
  await invoke("sftp_download", { sessionId, remotePath, localPath, taskId });
}

/** 从本地路径上传（Rust 直连，带进度事件）。 */
export async function sftpUpload(
  sessionId: string,
  localPath: string,
  remotePath: string,
  taskId: string,
): Promise<void> {
  const invoke = await getInvoke();
  await invoke("sftp_upload", { sessionId, localPath, remotePath, taskId });
}

/** 订阅传输进度。 */
export async function subscribeTransferProgress(
  handler: (payload: { taskId: string; transferred: number; total: number; percent: number }) => void,
): Promise<() => void> {
  if (!isTauriRuntime()) return () => {};
  const { listen } = await import("@tauri-apps/api/event");
  return listen<{ taskId: string; transferred: number; total: number; percent: number }>(
    "sftp://progress",
    (event) => handler(event.payload),
  );
}

/** 打开保存对话框，返回选中的本地路径。 */
export async function pickSavePath(defaultName: string): Promise<string | null> {
  if (!isTauriRuntime()) return null;
  const { save } = await import("@tauri-apps/plugin-dialog");
  const chosen = await save({ defaultPath: defaultName });
  return typeof chosen === "string" ? chosen : null;
}

/** 打开文件选择对话框，返回选中的本地路径。 */
export async function pickOpenPath(): Promise<string | null> {
  if (!isTauriRuntime()) return null;
  const { open } = await import("@tauri-apps/plugin-dialog");
  const chosen = await open({ multiple: false, directory: false });
  return typeof chosen === "string" ? chosen : null;
}

/** 读取本地文件为 base64（上传用）。 */
export async function readLocalFileAsBase64(file: File): Promise<string> {
  const buffer = await file.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/** base64 转 Blob（下载用）。 */
export function base64ToBlob(base64: string, type = "application/octet-stream"): Blob {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return new Blob([bytes], { type });
}