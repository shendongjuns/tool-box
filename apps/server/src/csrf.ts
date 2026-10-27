import type { FastifyInstance } from "fastify";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/** 桌面端 WebView 的 origin（Windows 上是 http://tauri.localhost，其它平台是 tauri://localhost）。 */
function isDesktopOrigin(origin: string): boolean {
  return (
    origin.startsWith("tauri://") ||
    origin.startsWith("http://tauri.localhost") ||
    origin.startsWith("https://tauri.localhost")
  );
}

/**
 * 不需要 CSRF 校验的「认证入口」路径。
 *
 * 这些接口本身就是用来换取令牌的，调用时必然没有 Authorization 头，
 * 且它们的响应只返回 token / 状态，不执行任何有副作用的业务操作 ——
 * 不构成 CSRF 攻击面（攻击者拿到 token 也没用，因为他读不到响应体）。
 */
const AUTH_ENTRY_PATHS = new Set([
  "/api/auth/bootstrap",
  "/api/auth/login",
  "/api/auth/desktop-login",
]);

function hostOf(value: string | undefined): string | null {
  if (!value) return null;
  try {
    // Origin 是完整 URL；Host 头是裸 host，用占位协议统一解析
    const url = value.includes("://") ? new URL(value) : new URL(`http://${value}`);
    return url.host;
  } catch {
    return null;
  }
}

/**
 * CSRF 防护。
 *
 * 核心原则：**CSRF 只威胁「浏览器自动携带凭证」的场景**（Cookie）。
 * 本服务的跨源客户端全部使用 `Authorization: Bearer` ——
 * 浏览器不会自动附带这个头，恶意站点无法伪造，因此不需要 CSRF 校验。
 *
 * 历史上这里要求 Origin 与 Host 完全一致，导致局域网部署不可用：
 * 客户端页面在 http://192.168.1.100:8080，API 在 http://10.0.0.11:3000，
 * Origin 与 Host 天然不同，所有写请求被 403 拒绝。
 *
 * 现在的规则：
 * 1. 带 Authorization 头 → 放行（Bearer 模式，无 CSRF 风险）
 * 2. 无 Origin（curl / 原生客户端）→ 放行
 * 3. 桌面端 origin → 放行
 * 4. 仅**基于 Cookie 的浏览器会话**才校验 Origin 与 Host 同源
 *
 * 这样既保住 Cookie 场景的 CSRF 防护，又让 Bearer 客户端（含局域网）正常工作。
 */
export function registerOriginGuard(app: FastifyInstance): void {
  app.addHook("onRequest", async (request, reply) => {
    if (SAFE_METHODS.has(request.method)) return;

    /*
     * 认证入口放行。
     * 局域网部署时，客户端页面与服务端不同源，
     * 若这里拦下登录/注册，用户根本无法建立会话。
     */
    const pathOnly = (request.url.split("?")[0] ?? "").split("#")[0] ?? "";
    if (AUTH_ENTRY_PATHS.has(pathOnly)) return;

    /*
     * Bearer 模式直接放行。
     * 攻击者的页面无法读取受害者的 token，也无法让浏览器自动带上它，
     * 因此不存在 CSRF 攻击面。
     */
    if (request.headers.authorization) return;

    /*
     * 无 Origin 视为非浏览器客户端（curl、脚本、部分原生 App）。
     * 这类客户端同样不受 CSRF 影响。
     */
    const origin = request.headers.origin;
    if (!origin) return;

    if (isDesktopOrigin(origin)) return;

    /*
     * 走到这里说明：无 Authorization + 有 Origin，
     * 即「可能是靠 Cookie 认证的浏览器请求」—— 这才需要同源校验。
     */
    const originHost = hostOf(origin);
    if (!originHost) {
      return reply.status(403).send({ code: "ORIGIN_FORBIDDEN", message: "请求来源不被允许" });
    }

    const candidates = [
      hostOf(request.headers["x-forwarded-host"] as string | undefined),
      hostOf(request.headers.host),
    ].filter((value): value is string => value !== null);

    if (candidates.includes(originHost)) return;

    return reply.status(403).send({ code: "ORIGIN_FORBIDDEN", message: "请求来源不被允许" });
  });
}