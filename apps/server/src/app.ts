import Fastify, { type FastifyInstance } from "fastify";
import cookie from "@fastify/cookie";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import fastifyStatic from "@fastify/static";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { createNodeDatabase, type NodeDatabase } from "@toolbox/data";
import { AuthService } from "./auth/service.js";
import { extractToken } from "./plugins/auth.js";
import { loadConfig, type AppConfig } from "./config.js";
import { registerOriginGuard } from "./csrf.js";
import { registerErrorHandler, unauthorized } from "./plugins/errors.js";
import { registerAuthRoutes } from "./routes/auth.js";
import { registerDashboardRoutes } from "./routes/dashboard.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerServerRoutes } from "./routes/servers.js";
import { registerSettingsRoutes } from "./routes/settings.js";
import { registerToolsRoutes } from "./routes/tools.js";
import "./types.js";

export interface BuildAppOptions {
  config?: AppConfig;
  databasePath?: string;
  webDistPath?: string;
}

export interface BuiltApp {
  app: FastifyInstance;
  db: NodeDatabase;
}

const LOGIN_RATE_LIMIT = { max: 10, timeWindow: "1 minute" } as const;

/** 依次尝试这些目录作为前端构建产物（开发 / 本地生产 / Docker）。 */
function findWebDist(explicit?: string): string | null {
  const candidates = explicit
    ? [explicit]
    : [
        resolve(process.cwd(), "public"),
        resolve(process.cwd(), "apps/server/public"),
        resolve(process.cwd(), "../../apps/web/dist"),
      ];
  for (const dir of candidates) {
    if (existsSync(resolve(dir, "index.html"))) return dir;
  }
  return null;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<BuiltApp> {
  const config = options.config ?? loadConfig();
  const db = createNodeDatabase(options.databasePath ?? config.DATABASE_PATH);

  const app = Fastify({
    logger: config.LOG_LEVEL === "silent" ? false : { level: config.LOG_LEVEL },
    trustProxy: config.TRUST_PROXY,
    bodyLimit: 1024 * 1024,
  });

  app.decorate("config", config);
  app.decorate("db", db.db);
  app.decorate("authService", new AuthService(db.db, config));
  app.decorateRequest("auth");

  await app.register(cookie);
  await app.register(helmet, { contentSecurityPolicy: false });

  /**
   * 桌面端是跨源客户端（Tauri 的 origin 是 tauri://localhost），
   * 用 Bearer 令牌访问云端，因此必须放开 CORS。
   * credentials 保持 false：跨源请求不携带 Cookie，只认 Authorization 头。
   */
  await app.register(cors, {
    origin: true,
    credentials: false,
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "X-Toolbox-Client"],
    maxAge: 600,
  });

  await app.register(rateLimit, { global: false });

  app.decorate("requireAuth", async (request, reply) => {
    const token = extractToken(request, config.cookieName);
    if (!token) {
      return reply.status(401).send({ code: "UNAUTHENTICATED", message: unauthorized().message });
    }
    const auth = await app.authService.authenticate(token);
    if (!auth) {
      return reply.status(401).send({ code: "UNAUTHENTICATED", message: "登录已过期，请重新登录" });
    }
    request.auth = auth;
  });

  registerErrorHandler(app);
  registerOriginGuard(app);

  await app.register(async (scope) => {
    await scope.register(rateLimit, {
      global: false,
      max: LOGIN_RATE_LIMIT.max,
      timeWindow: LOGIN_RATE_LIMIT.timeWindow,
    });
    await registerAuthRoutes(scope);
  });

  await registerServerRoutes(app);
  await registerSettingsRoutes(app);
  await registerToolsRoutes(app);
  await registerDashboardRoutes(app);
  await registerHealthRoutes(app);

  // 可选：直接托管前端构建产物（用 nginx 时可以把 public/ 去掉）
  const distPath = findWebDist(options.webDistPath);
  if (distPath) {
    await app.register(fastifyStatic, { root: distPath, prefix: "/" });
    app.setNotFoundHandler((request, reply) => {
      if (request.method !== "GET" || request.url.startsWith("/api/")) {
        return reply.status(404).send({ code: "NOT_FOUND", message: "资源不存在" });
      }
      return reply.sendFile("index.html");
    });
  }

  return { app, db };
}