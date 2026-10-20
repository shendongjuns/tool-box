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

/**
 * 业务接口封装：所有客户端（网页 / 桌面本地 / 桌面云端）共用同一套方法签名。
 * 数据源差异只体现在 transport 上，页面代码不感知。
 */
export function createApi(transport: ApiTransport) {
  const get = <T>(path: string) => transport.request<T>({ path });
  const send = <T>(path: string, method: "POST" | "PUT" | "PATCH" | "DELETE", body?: unknown) =>
    transport.request<T>({ path, method, body });

  return {
    getBootstrap: () => get<BootstrapStatus>("/api/auth/bootstrap"),

    bootstrap: (body: { username: string; password: string; displayName?: string; setupToken?: string }) =>
      send<LoginResponse>("/api/auth/bootstrap", "POST", body),

    login: (body: LoginRequest) => send<LoginResponse>("/api/auth/login", "POST", body),

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

    getSettings: () => get<{ values: Record<string, string | number | boolean>; updatedAt: number | null }>("/api/settings"),

    putSettings: (body: PutSettingsRequest) =>
      send<{ values: Record<string, string | number | boolean>; updatedAt: number }>(
        "/api/settings",
        "PUT",
        body,
      ),

    listTools: () => get<ToolListResponse>("/api/tools"),

    patchTool: (id: string, body: PatchToolRequest) =>
      send<ToolListResponse>(`/api/tools/${encodeURIComponent(id)}`, "PATCH", body),

    touchTool: (id: string) => send<{ ok: true }>(`/api/tools/${encodeURIComponent(id)}/touch`, "POST"),

    dashboard: () => get<DashboardResponse>("/api/dashboard"),
  };
}

export type Api = ReturnType<typeof createApi>;
