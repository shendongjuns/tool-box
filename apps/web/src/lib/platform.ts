/**
 * 运行环境判定。
 *
 * 桌面端（Tauri）在 window 上注入 __TAURI_INTERNALS__；构建期还会注入 __APP_TARGET__
 * （见 vite.config.ts 的 define，网页端为 "web"）。
 */
export type DataSource = "local" | "cloud";

export const APP_TARGET: "web" | "desktop" =
  typeof __APP_TARGET__ === "undefined" ? "web" : __APP_TARGET__;

export function isTauriRuntime(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

/** 是否运行在桌面壳内（构建目标或运行时任一命中）。 */
export function isDesktop(): boolean {
  return APP_TARGET === "desktop" || isTauriRuntime();
}
