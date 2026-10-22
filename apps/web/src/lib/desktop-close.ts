import { isTauriRuntime } from "./platform";

/**
 * 窗口关闭行为：**始终隐藏到托盘**，不弹确认框。
 *
 * 真正退出走托盘右键菜单的「退出 ToolBox」，避免误关导致后台服务被中断。
 */
export async function listenCloseRequest(handler: () => void): Promise<() => void> {
  if (!isTauriRuntime()) return () => {};
  const { listen } = await import("@tauri-apps/api/event");
  return listen("app://close-requested", handler);
}

/** 隐藏到托盘。 */
export async function hideToTray(): Promise<void> {
  if (!isTauriRuntime()) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("hide_to_tray");
}

/** 彻底退出应用（仅托盘菜单使用）。 */
export async function quitApp(): Promise<void> {
  if (!isTauriRuntime()) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("quit_app");
}
