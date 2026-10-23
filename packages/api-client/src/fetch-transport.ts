import { ApiError, type ApiTransport, type RequestOptions } from "./types.js";

export interface FetchTransportOptions {
  baseUrl: string;
  credentials?: "include" | "omit";
  source?: "cloud" | "local";
  /** 每次请求时求值的额外请求头（桌面端注入 Bearer） */
  headers?: () => Record<string, string>;
  /**
   * 请求超时（毫秒）。默认 3000。
   *
   * 云端地址不可达时浏览器会挂很久（TCP 超时可能 30s+），
   * 登录页的「正在连接…」会一直转下去。这里强制 3 秒内出结果。
   */
  timeoutMs?: number;
}

/** 默认请求超时：3 秒。 */
export const DEFAULT_TIMEOUT_MS = 3000;

/** 把网络层异常统一成 ApiError，避免上层拿到 "Failed to fetch" 这种无从处理的错误。 */
function toNetworkError(error: unknown): ApiError {
  if (error instanceof ApiError) return error;
  if (error instanceof DOMException && error.name === "AbortError") {
    return new ApiError(0, "ABORTED", "请求已取消");
  }
  return new ApiError(
    0,
    "NETWORK_ERROR",
    "无法连接服务器，请检查地址与网络后重试",
  );
}

export function createFetchTransport(options: FetchTransportOptions): ApiTransport {
  const base = options.baseUrl.replace(/\/$/, "");
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  return {
    credentials: options.credentials ?? "include",
    source: options.source ?? "cloud",
    async request<T>(request: RequestOptions): Promise<T> {
      const method = request.method ?? "GET";
      let response: Response;

      // 超时控制：AbortController + setTimeout，保证 3 秒内一定有结果。
      // 调用方自带 signal 时两者合并（任一触发都中断）。
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      if (request.signal) {
        if (request.signal.aborted) controller.abort();
        else request.signal.addEventListener("abort", () => controller.abort(), { once: true });
      }

      try {
        response = await fetch(`${base}${request.path}`, {
          method,
          credentials: options.credentials ?? "include",
          headers: {
            ...(request.body === undefined ? {} : { "content-type": "application/json" }),
            accept: "application/json",
            ...(options.headers?.() ?? {}),
          },
          ...(request.body === undefined ? {} : { body: JSON.stringify(request.body) }),
          signal: controller.signal,
        });
      } catch (error) {
        // 主动 abort 分两种：调用方取消 vs 超时，给不同文案
        if (controller.signal.aborted && !request.signal?.aborted) {
          throw new ApiError(
            0,
            "TIMEOUT",
            `连接超时（超过 ${Math.round(timeoutMs / 1000)} 秒无响应），请检查地址与网络`,
          );
        }
        throw toNetworkError(error);
      } finally {
        clearTimeout(timer);
      }

      if (response.status === 204) return undefined as T;

      const text = await response.text();
      let data: unknown;
      try {
        data = text.length > 0 ? JSON.parse(text) : undefined;
      } catch {
        data = undefined;
      }

      if (!response.ok) {
        const error = data as { code?: string; message?: string; details?: unknown } | undefined;
        throw new ApiError(
          response.status,
          error?.code ?? "REQUEST_FAILED",
          error?.message ?? `请求失败（HTTP ${response.status}）`,
          error?.details,
        );
      }
      return data as T;
    },
  };
}
