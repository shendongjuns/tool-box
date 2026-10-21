import * as React from "react";
import { createApi, createFetchTransport, type Api } from "@toolbox/api-client";
import { useDataSource } from "./data-source";
import { authHeaderFor, getLocalBaseUrl, hasLocalApi } from "./desktop";
import { isTauriRuntime } from "./platform";

const ApiContext = React.createContext<Api | null>(null);

/**
 * API 实例按「数据源 + 地址 + 令牌」缓存。
 *
 * 网页端：同源 fetch + Cookie。
 * 桌面端云端：直连用户配置的服务器，带 Bearer。
 * 桌面端本地：直连 127.0.0.1 上的本地服务，带本地令牌。
 */
let cachedKey = "";
let cachedApi: Api | null = null;

export function getApi(): Api {
  const { source, cloudBaseUrl } = useDataSource.getState();
  const tauri = isTauriRuntime();
  const key = [source, cloudBaseUrl, authHeaderFor(source).authorization ?? ""].join("|");
  if (cachedApi && cachedKey === key) return cachedApi;

  // 本地服务未就绪时不抛异常（会在渲染期间炸掉整个树），
  // 而是指向一个必然失败的地址，让请求层返回可读的错误。


  const baseUrl =
    source === "cloud" ? (tauri ? cloudBaseUrl : "") : hasLocalApi() ? getLocalBaseUrl() : "http://127.0.0.1:1";

  cachedApi = createApi(
    createFetchTransport({
      baseUrl,
      source,
      // 网页端同源用 Cookie；桌面端一律 Bearer，不需要 Cookie
      credentials: tauri ? "omit" : "include",
      headers: () => (tauri ? authHeaderFor(source) : {}),
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
  const source = useDataSource((state) => state.source);
  const cloudBaseUrl = useDataSource((state) => state.cloudBaseUrl);

  const api = React.useMemo(() => getApi(), [source, cloudBaseUrl]);
  return <ApiContext.Provider value={api}>{children}</ApiContext.Provider>;
}

export function useApi(): Api {
  const api = React.useContext(ApiContext);
  if (!api) throw new Error("useApi 必须在 ApiProvider 内使用");
  return api;
}