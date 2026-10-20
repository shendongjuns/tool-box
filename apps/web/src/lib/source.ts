import { isDesktop } from "./platform";

/**
 * 数据源描述：UI 徽标、设置页与登录页文案共用。
 *
 * 本地与云端是两套**完全独立**的数据（各自有库、各自有账号），
 * 只在设置里切换「使用哪一套」，不做任何同步或覆盖。
 */
export const DATA_SOURCES = {
  local: {
    id: "local" as const,
    label: "本地数据",
    short: "本地",
    description: "数据只保存在这台电脑上，断网也能用。与云端数据完全独立。",
    requiresNetwork: false,
  },
  cloud: {
    id: "cloud" as const,
    label: "云端数据",
    short: "云端",
    description: "数据保存在你的服务器上，网页端与其它设备共享同一份数据。",
    requiresNetwork: true,
  },
};

export function canSwitchSource(): boolean {
  return isDesktop();
}
