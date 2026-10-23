import { ApiError, type ApiTransport, type RequestOptions } from "./types.js";

export interface TauriTransportOptions {
  baseUrl: string;
  /** 每次请求时求值的额外请求头（桌面端注入 Bearer） */
  headers?: () => Record<string, string>;
}

/**
 * 桌面端传输层：所有请求经 Rust 的 http_request 命令转发。
 *
 * 为什么需要它：WebView 的 CSP 是 `connect-src 'self' http://127.0.0.1:* http://localhost:*`，
 * 渲染进程不能直连云端服务器（更宽泛的 https: 会允许任何脚本把令牌发去任意站点）。
 * 由 Rust 侧统一出网后，渲染层即使被注入脚本也发不出数据。
 */
/**
 * Rust 命令调用签名（与 @tauri-apps/api/core 的 invoke 兼容）。
 *
 * 不直接在 packages 里 import Tauri API —— packages 不依赖它，
 * 构建时 Rollup 也无法解析。由调用方（apps/web）注入真实实现。
 */
export type TauriInvoke = (
  command: string,
  args?: Record<string, unknown>,
) => Promise<unknown>;

export function createTauriTransport(
  options: TauriTransportOptions & { invoke: TauriInvoke },
): ApiTransport {
  const base = options.baseUrl.replace(/\/$/, "");
  const invoke = options.invoke;

  return {
    // 桌面端不用 Cookie（Bearer 已足够），统一 omit
    credentials: "omit",
    source: "cloud",
    async request<T>(request: RequestOptions): Promise<T> {
      let result: { status: number; body: string };
      try {
        result = (await invoke("http_request", {
          method: request.method ?? "GET",
          url: `${base}${request.path}`,
          ...(request.body === undefined ? {} : { body: JSON.stringify(request.body) }),
          headers: {
            ...(request.body === undefined ? {} : { "content-type": "application/json" }),
            accept: "application/json",
            "X-Toolbox-Client": "desktop",
            ...(options.headers?.() ?? {}),
          },
        })) as { status: number; body: string };
      } catch (error) {
        throw new ApiError(
          0,
          "NETWORK_ERROR",
          error instanceof Error ? `无法连接服务器：${error.message}` : "无法连接服务器，请检查地址与网络",
        );
      }

      if (result.status === 204) return undefined as T;

      let data: unknown;
      try {
        data = result.body.length > 0 ? JSON.parse(result.body) : undefined;
      } catch {
        data = undefined;
      }

      if (result.status < 200 || result.status >= 300) {
        const error = data as { code?: string; message?: string; details?: unknown } | undefined;
        throw new ApiError(
          result.status,
          error?.code ?? "REQUEST_FAILED",
          error?.message ?? `请求失败（HTTP ${result.status}）`,
          error?.details,
        );
      }
      return data as T;
    },
  };
}