import * as React from "react";
import { createApi, createFetchTransport, type Api } from "@toolbox/api-client";
import { useDataSource } from "./data-source";
import { authHeaderFor, getLocalBaseUrl } from "./desktop";
import { isTauriRuntime } from "./platform";

const ApiContext = React.createContext<Api | null>(null);

/**
 * API 实例按「数据源 + 地址 + 令牌」缓存。
 *
 * 网页端：同源 fetch + Cookie。
 * 桌面端云端：直连所选服务器，带 Bearer。
 * 桌面端本地：直连 127.0.0.1 上的本地服务，带本地令牌。
 */
let cachedKey = "";
let cachedApi: Api | null = null;

export function getApi(): Api {
  const { type, cloudBaseUrl } = useDataSource.getState();
  const tauri = isTauriRuntime();
  const key = [type, cloudBaseUrl, authHeaderFor(type).authorization ?? ""].join("|");
  if (cachedApi && cachedKey === key) return cachedApi;

  /*
   * 本地数据源：端口在启动时异步解析。正常情况下 initDesktopBridge 已经 await 过，
   * 这里再兜底一次 —— 如果还没就绪，指向一个必然失败的地址，
   * 由调用方（数据源切换 / 登录页 bootstrap 查询）给出可读错误。
   */
  const baseUrl =
    type === "cloud" ? (tauri ? cloudBaseUrl : "") : getLocalBaseUrl() || "http://127.0.0.1:1";

  cachedApi = createApi(
    createFetchTransport({
      baseUrl,
      source: type,
      // 网页端同源用 Cookie；桌面端一律 Bearer，不需要 Cookie
      credentials: tauri ? "omit" : "include",
      headers: () => (tauri ? authHeaderFor(type) : {}),
    }),
    { desktop: tauri },
  );
  cachedKey = key;
  return cachedApi;
}

/** 令牌变化（登录 / 登出）后必须让缓存失效。 */
export function invalidateApiCache(): void {
  cachedKey = "";
  cachedApi = null;
}

export function ApiProvider({ children }: { children: React.ReactNode }) {
  const activeId = useDataSource((state) => state.activeId);
  const cloudBaseUrl = useDataSource((state) => state.cloudBaseUrl);

  const api = React.useMemo(() => getApi(), [activeId, cloudBaseUrl]);
  return <ApiContext.Provider value={api}>{children}</ApiContext.Provider>;
}

export function useApi(): Api {
  const api = React.useContext(ApiContext);
  if (!api) throw new Error("useApi 必须在 ApiProvider 内使用");
  return api;
}