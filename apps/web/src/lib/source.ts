import { useDataSource } from "./data-source";
import { isDesktop } from "./platform";

/**
 * 数据源相关的小工具。
 *
 * 注意：页面本身不区分本地 / 云端，这里只用于「切换数据源」的 UI 与文案。
 */
export function canSwitchSource(): boolean {
  return isDesktop();
}

/** 当前数据源是否免登录（仅桌面端本地）。 */
export function isLocalSource(): boolean {
  return isDesktop() && useDataSource.getState().type === "local";
}

export const SOURCE_NOTES = {
  local: "数据只保存在这台电脑上，无需登录，断网也能用。",
  cloud: "数据保存在该服务器上，需要账号密码登录。",
} as const;
