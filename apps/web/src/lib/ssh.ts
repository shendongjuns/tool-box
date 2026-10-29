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
  /** known_hosts.json 的绝对路径（Rust 侧 data 目录） */
  knownHostsPath?: string;
  /** 用户已确认信任新指纹（指纹变化后手动确认时为 true） */
  trustNewHost?: boolean;
}

/** 已知主机指纹记录。 */
export interface KnownHostRecord {
  algorithm: string;
  fingerprint: string;
}

/**
 * 取 known_hosts.json 的绝对路径。
 *
 * 由 Rust 侧计算（数据目录跟着 exe 走），前端只负责传递。
 */
export async function getKnownHostsPath(): Promise<string | null> {
  if (!isTauriRuntime()) return null;
  try {
    const invoke = await getInvoke();
    return await invoke<string>("known_hosts_path");
  } catch {
    return null;
  }
}

/** 查询某主机已保存的指纹。 */
export async function getKnownHost(
  host: string,
  port: number,
): Promise<KnownHostRecord | null> {
  const path = await getKnownHostsPath();
  if (!path) return null;
  const invoke = await getInvoke();
  return invoke<KnownHostRecord | null>("ssh_known_host", {
    knownHostsPath: path,
    host,
    port,
  });
}

/** 显式信任某主机的新指纹（用户手动确认后调用）。 */
export async function trustKnownHost(
  host: string,
  port: number,
  algorithm: string,
  fingerprint: string,
): Promise<void> {
  const path = await getKnownHostsPath();
  if (!path) return;
  const invoke = await getInvoke();
  await invoke("ssh_trust_host", {
    knownHostsPath: path,
    host,
    port,
    algorithm,
    fingerprint,
  });
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

/** 测试连接（不建立持久会话），返回各阶段耗时。 */
export async function sshTest(config: Omit<ConnectConfig, "sessionId" | "cols" | "rows">): Promise<{
  handshakeMs: number;
  authMs: number;
  totalMs: number;
}> {
  const invoke = await getInvoke();
  return invoke<{ handshakeMs: number; authMs: number; totalMs: number }>("ssh_test", {
    config: { ...config, sessionId: "test", cols: 80, rows: 24 },
  });
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
  // Rust 侧理论上总是返回 String，但连接中断时可能拿到 undefined
  const result = await invoke<string | undefined>("ssh_exec", { sessionId, command, timeoutMs });
  return result ?? "";
}

/**
 * 探测服务器 TCP 延迟。
 *
 * 用 Rust 的 tcp_ping 做一次 connect，测的是网络往返 ——
 * 比完整 SSH 握手快得多，适合列表页逐条展示。
 */
export async function probeServerLatency(
  host: string,
  port: number,
  timeoutMs = 3000,
): Promise<{ kind: "ok" | "timeout" | "error"; ms: number; message?: string }> {
  try {
    const invoke = await getInvoke();
    const ms = await invoke<number>("tcp_ping", { host, port, timeoutMs });
    return { kind: "ok", ms };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { kind: message.includes("超时") ? "timeout" : "error", ms: 0, message };
  }
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
    /*
     * listen() 返回的是 async 闭包。
     * 窗口销毁 / 页面重载后，内部的 unregisterListener 可能已不存在，
     * 会抛 TypeError 或产生 unhandled rejection，所以统一吞掉。
     */
    for (const fn of [unlistenData, unlistenClosed]) {
      try {
        // 返回类型是 void，但实现里是 async 闭包，所以按 unknown 处理
        const result: unknown = fn();
        if (result instanceof Promise) result.catch(() => {});
      } catch {
        /* 已失效，忽略 */
      }
    }
  };
}

// ---------------- SFTP ----------------

export async function sftpList(sessionId: string, path: string): Promise<SftpEntry[]> {
  const invoke = await getInvoke();
  return invoke<SftpEntry[]>("sftp_list", { sessionId, path });
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
  try {
    // 注意：这里直接调用同文件的 sshExec。
    // 之前写成 await import("./ssh") 是自我导入，会触发 Rollup 警告，
    // 而且动态导入自己这个模块没有意义（模块早就在加载中）。
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