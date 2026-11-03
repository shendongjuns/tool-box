import type {
  CreateServerRequest,
  Server,
  ServerListResponse,
  BootstrapStatus,
  ChangePasswordRequest,
  DashboardResponse,
  DesktopLoginResponse,
  LoginRequest,
  LoginResponse,
  MeResponse,
  PatchToolRequest,
  PutSettingsRequest,
  UpdateServerRequest,
  SessionListResponse,
  ToolListResponse,
  ListBackupsResponse,
  CreateBackupResponse,
  DeleteBackupResponse,
  RestoreBackupResponse,
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

    changePassword: (body: ChangePasswordRequest) => send<void>("/api/auth/password", "POST", body),

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

    /*
     * 数据库备份。
     *
     * 恢复会整体替换数据库，成功后当前会话立即失效 ——
     * 调用方需要引导用户重新登录。
     */
    listBackups: () => get<ListBackupsResponse>("/api/backup"),

    /**
     * 备份下载地址。
     *
     * 网页端直接用 <a href> 或 window.open 触发浏览器下载；
     * 桌面端没有这个能力（WebView 里不能直接下文件到磁盘），
     * 需要走 Rust 的导出命令 —— 所以这里返回 null 让前端分支处理。
     */
    backupDownloadUrl: (name: string) => `/api/backup/${encodeURIComponent(name)}`,

    createBackup: () => send<CreateBackupResponse>("/api/backup", "POST"),

    /**
     * 导入外部备份文件。
     *
     * 以原始字节上传（不是 JSON），文件名通过 X-Backup-Name 头传递 ——
     * body 已被文件内容占用，没有位置放元数据。
     */
    importBackup: (file: Blob, fileName: string) =>
      transport.request<CreateBackupResponse>({
        path: "/api/backup/import",
        method: "POST",
        body: file,
        headers: () => ({ "X-Backup-Name": fileName }),
      }),

    deleteBackup: (name: string) =>
      send<DeleteBackupResponse>(`/api/backup/${encodeURIComponent(name)}`, "DELETE"),

    restoreBackup: (name: string) =>
      send<RestoreBackupResponse>(`/api/backup/${encodeURIComponent(name)}/restore`, "POST"),

    listTools: () => get<ToolListResponse>("/api/tools"),

    patchTool: (id: string, body: PatchToolRequest) =>
      send<ToolListResponse>(`/api/tools/${encodeURIComponent(id)}`, "PATCH", body),

    touchTool: (id: string) =>
      send<{ ok: true }>(`/api/tools/${encodeURIComponent(id)}/touch`, "POST"),

    dashboard: () => get<DashboardResponse>("/api/dashboard"),

    listServers: () => get<ServerListResponse>("/api/servers"),

    createServer: (body: CreateServerRequest) => send<Server>("/api/servers", "POST", body),

    updateServer: (id: string, body: UpdateServerRequest) =>
      send<Server>(`/api/servers/${encodeURIComponent(id)}`, "PUT", body),

    deleteServer: (id: string) => send<void>(`/api/servers/${encodeURIComponent(id)}`, "DELETE"),

    getServerCredential: (id: string) =>
      send<{
        id: string;
        host: string;
        port: number;
        username: string;
        authType: "password" | "key";
        password: string | null;
        privateKey: string | null;
        passphrase: string | null;
      }>(`/api/servers/${encodeURIComponent(id)}/credential`, "POST"),

    /** 供 transport 注入的客户端标识头 */
    clientHeaders: clientHeader,
  };
}

export type Api = ReturnType<typeof createApi>;
