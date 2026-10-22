import { isTauriRuntime } from "./platform";

export type CloseBehavior = "ask" | "tray" | "quit";

const STORAGE_KEY = "toolbox.closeBehavior";

export function readCloseBehavior(): CloseBehavior {
  if (typeof window === "undefined") return "ask";
  const value = localStorage.getItem(STORAGE_KEY);
  return value === "tray" || value === "quit" ? value : "ask";
}

export function writeCloseBehavior(behavior: CloseBehavior): void {
  localStorage.setItem(STORAGE_KEY, behavior);
}

/**
 * 监听窗口关闭请求。
 *
 * 桌面端点击标题栏 × 时，Rust 侧会拦下关闭事件并发出 `app://close-requested`，
 * 这里根据用户设置决定：弹框询问 / 直接最小化到托盘 / 直接退出。
 */
export async function listenCloseRequest(handler: () => void): Promise<() => void> {
  if (!isTauriRuntime()) return () => {};

  const { listen } = await import("@tauri-apps/api/event");
  const unlisten = await listen("app://close-requested", handler);
  return unlisten;
}

/** 最小化到托盘。 */
export async function hideToTray(): Promise<void> {
  if (!isTauriRuntime()) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("hide_to_tray");
}

/** 彻底退出应用。 */
export async function quitApp(): Promise<void> {
  if (!isTauriRuntime()) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("quit_app");
}
