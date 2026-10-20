import { ApiError, type ApiTransport, type RequestOptions } from "./types.js";

export interface FetchTransportOptions {
  baseUrl: string;
  credentials?: "include" | "omit";
  source?: "cloud" | "local";
  /** 额外请求头（桌面端注入 Bearer 等） */
  headers?: () => Record<string, string>;
}

export function createFetchTransport(options: FetchTransportOptions): ApiTransport {
  const base = options.baseUrl.replace(/\/$/, "");

  return {
    credentials: options.credentials ?? "include",
    source: options.source ?? "cloud",
    async request<T>(request: RequestOptions): Promise<T> {
      const method = request.method ?? "GET";
      const response = await fetch(`${base}${request.path}`, {
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

      if (response.status === 204) return undefined as T;

      const text = await response.text();
      const data: unknown = text.length > 0 ? JSON.parse(text) : undefined;

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
