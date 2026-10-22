import type {
  BootstrapStatus,
  ChangePasswordRequest,
  DashboardResponse,
  DesktopLoginResponse,
  LoginRequest,
  LoginResponse,
  MeResponse,
  PatchToolRequest,
  PutSettingsRequest,
  SessionListResponse,
  ToolListResponse,
} from "@toolbox/contracts";
import type { ApiTransport } from "./types.js";

export interface CreateApiOptions {
  /** 桌面端：让服务端识别会话类型并返回 Bearer 令牌 */
  desktop?: boolean;
}

/**
 * 业务接口封装：所有客户端（网页 / 桌面本地 / 桌面云端）共用同一套方法签名。
 * 数据源差异只体现在 transport 上，页面代码不感知。
 */
export function createApi(transport: ApiTransport, options: CreateApiOptions = {}) {
  const clientHeader = options.desktop ? { "x-toolbox-client": "desktop" } : {};

  const get = <T>(path: string) => transport.request<T>({ path });
  const send = <T>(path: string, method: "POST" | "PUT" | "PATCH" | "DELETE", body?: unknown) =>
    transport.request<T>({ path, method, body });

  return {
    getBootstrap: () => get<BootstrapStatus>("/api/auth/bootstrap"),

    /** 创建唯一账号：仅当库里没有用户时服务端才接受。 */
    bootstrap: (body: { username: string; password: string; displayName?: string }) =>
      transport.request<LoginResponse>({ path: "/api/auth/bootstrap", method: "POST", body }),

    /** 桌面端走 desktop-login 才拿得到 token；网页端走 login 写 Cookie。 */
    login: (body: LoginRequest) =>
      options.desktop
        ? transport
            .request<DesktopLoginResponse>({
              path: "/api/auth/desktop-login",
              method: "POST",
              body,
            })
            .then((result) => ({
              user: result.user,
              token: result.token,
              session: {
                createdAt: Date.now(),
                lastUsedAt: Date.now(),
                expiresAt: result.expiresAt,
                kind: "desktop" as const,
              },
            }))
        : transport.request<LoginResponse>({ path: "/api/auth/login", method: "POST", body }),

    desktopLogin: (body: LoginRequest) =>
      send<DesktopLoginResponse>("/api/auth/desktop-login", "POST", body),

    logout: () => send<void>("/api/auth/logout", "POST"),

    me: () => get<MeResponse>("/api/auth/me"),

    changePassword: (body: ChangePasswordRequest) =>
      send<void>("/api/auth/password", "POST", body),

    listSessions: () => get<SessionListResponse>("/api/auth/sessions"),

    revokeSession: (id: string) =>
      send<void>(`/api/auth/sessions/${encodeURIComponent(id)}`, "DELETE"),

    revokeAllSessions: () => send<void>("/api/auth/sessions/revoke-all", "POST"),

    getSettings: () =>
      get<{ values: Record<string, string | number | boolean>; updatedAt: number | null }>(
        "/api/settings",
      ),

    putSettings: (body: PutSettingsRequest) =>
      send<{ values: Record<string, string | number | boolean>; updatedAt: number }>(
        "/api/settings",
        "PUT",
        body,
      ),

    listTools: () => get<ToolListResponse>("/api/tools"),

    patchTool: (id: string, body: PatchToolRequest) =>
      send<ToolListResponse>(`/api/tools/${encodeURIComponent(id)}`, "PATCH", body),

    touchTool: (id: string) =>
      send<{ ok: true }>(`/api/tools/${encodeURIComponent(id)}/touch`, "POST"),

    dashboard: () => get<DashboardResponse>("/api/dashboard"),

    /** 供 transport 注入的客户端标识头 */
    clientHeaders: clientHeader,
  };
}

export type Api = ReturnType<typeof createApi>;