import { ApiError, type ApiTransport, type RequestOptions } from "./types.js";

export interface FetchTransportOptions {
  baseUrl: string;
  credentials?: "include" | "omit";
  source?: "cloud" | "local";
  /** 每次请求时求值的额外请求头（桌面端注入 Bearer） */
  headers?: () => Record<string, string>;
}

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

  return {
    credentials: options.credentials ?? "include",
    source: options.source ?? "cloud",
    async request<T>(request: RequestOptions): Promise<T> {
      const method = request.method ?? "GET";
      let response: Response;

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
          ...(request.signal ? { signal: request.signal } : {}),
        });
      } catch (error) {
        throw toNetworkError(error);
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
