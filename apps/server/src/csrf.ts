import type { FastifyInstance } from "fastify";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * 最简 CSRF 防护：非安全方法校验 Origin。
 *
 * Cookie 已是 SameSite=Lax，这里是第二道防线；桌面端用 Bearer 不带 Cookie，直接放行。
 * PUBLIC_ORIGIN 支持逗号分隔的多个来源（开发时的 5173 与生产域名）。
 */
export function registerOriginGuard(app: FastifyInstance): void {
  const allowed = app.config.PUBLIC_ORIGIN.split(",")
    .map((item) => item.trim().replace(/\/$/, ""))
    .filter((item) => item.length > 0);

  app.addHook("onRequest", async (request, reply) => {
    if (SAFE_METHODS.has(request.method)) return;
    if (request.headers.authorization) return; // Bearer 天然免疫 CSRF

    const origin = request.headers.origin;
    if (!origin) return; // 同源非浏览器客户端（curl/测试）不带 Origin
    if (allowed.includes(origin.replace(/\/$/, ""))) return;

    return reply.status(403).send({ code: "ORIGIN_FORBIDDEN", message: "请求来源不被允许" });
  });
}
