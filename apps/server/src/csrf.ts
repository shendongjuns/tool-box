import type { FastifyInstance } from "fastify";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/** 桌面端 WebView 的 origin（Windows 上是 http://tauri.localhost，其它平台是 tauri://localhost）。 */
function isDesktopOrigin(origin: string): boolean {
  return origin.startsWith("tauri://") || origin.startsWith("http://tauri.localhost");
}

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
 * CSRF 防护：非安全方法校验 Origin 与本次请求的 Host 是否一致。
 *
 * 不需要配置域名，放在 nginx 后面也能用：
 * nginx 需要 `proxy_set_header Host $host`（或 X-Forwarded-Host），
 * 这里两者都认，因此无论是否改写 Host 都能正确判断。
 */
export function registerOriginGuard(app: FastifyInstance): void {
  app.addHook("onRequest", async (request, reply) => {
    if (SAFE_METHODS.has(request.method)) return;
    if (request.headers.authorization) return;

    const origin = request.headers.origin;
    if (!origin) return; // 非浏览器客户端不带 Origin
    if (isDesktopOrigin(origin)) return;

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
