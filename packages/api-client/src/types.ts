export type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export interface RequestOptions {
  method?: HttpMethod;
  path: string;
  body?: unknown;
  signal?: AbortSignal;
}

export interface ApiTransport {
  /** 是否携带凭据（网页端 Cookie） */
  credentials: "include" | "omit";
  /** 数据源标识，用于 UI 徽标与缓存隔离 */
  source: "cloud" | "local";
  request<T>(options: RequestOptions): Promise<T>;
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}
