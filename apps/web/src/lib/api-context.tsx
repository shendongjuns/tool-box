import * as React from "react";
import { createApi, createFetchTransport, type Api } from "@toolbox/api-client";
import { useDataSource } from "./data-source";
import { getCloudToken, getLocalBaseUrl } from "./desktop";
import { isTauriRuntime } from "./platform";

const ApiContext = React.createContext<Api | null>(null);

let cachedKey = "";
let cachedApi: Api | null = null;
let localToken: string | null = null;

/** 本地数据源的会话令牌（仅保存在内存，重启后需重新登录）。 */
export function setLocalToken(token: string | null): void {
  localToken = token;
  cachedKey = "";
}

export function readLocalToken(): string | null {
  return localToken;
}

/**
 * 按当前数据源构造 API 实例（带缓存）。
 *
 * - 网页端：同源 fetch + Cookie。
 * - 桌面端云端模式：直连用户配置的服务器，请求头带 Bearer。
 * - 桌面端本地模式：直连 127.0.0.1 上的本地服务，请求头带本地令牌。
 */
export function getApi(): Api {
  const { source, cloudBaseUrl } = useDataSource.getState();
  const key = `${source}|${cloudBaseUrl}|${localToken ?? ""}|${getCloudToken() ?? ""}`;
  if (cachedApi && cachedKey === key) return cachedApi;

  const tauri = isTauriRuntime();
  const baseUrl = source === "cloud" ? (tauri ? cloudBaseUrl : "") : getLocalBaseUrl();

  cachedApi = createApi(
    createFetchTransport({
      baseUrl,
      source,
      credentials: source === "cloud" && !tauri ? "include" : "omit",
      headers: () => {
        const result: Record<string, string> = {};
        if (!tauri) return result;
        const token = source === "local" ? localToken : getCloudToken();
        if (token) result.authorization = `Bearer ${token}`;
        return result;
      },
    }),
  );
  cachedKey = key;
  return cachedApi;
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