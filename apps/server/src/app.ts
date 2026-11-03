import Fastify, { type FastifyInstance } from "fastify";
import cookie from "@fastify/cookie";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import fastifyStatic from "@fastify/static";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { createNodeDatabase, purgeExpiredSessions, type NodeDatabase } from "@toolbox/data";
import { AuthService } from "./auth/service.js";
import { extractToken } from "./plugins/auth.js";
import { loadConfig, type AppConfig } from "./config.js";
import { registerOriginGuard } from "./csrf.js";
import { registerErrorHandler, unauthorized } from "./plugins/errors.js";
import { registerAuthRoutes } from "./routes/auth.js";
import { registerBackupRoutes } from "./routes/backup.js";
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
  /*
   * 记住实际使用的库路径。
   *
   * 测试和部分部署会通过 options.databasePath 覆盖配置里的路径，
   * 重新打开时必须用同一个 —— 否则恢复后连到的是另一个文件，
   * 表现为「恢复成功但数据没变」或直接报连接已关闭。
   */
  const resolvedDatabasePath = options.databasePath ?? config.DATABASE_PATH;

  const db = createNodeDatabase(resolvedDatabasePath);

  const app = Fastify({
    logger: config.LOG_LEVEL === "silent" ? false : { level: config.LOG_LEVEL },
    trustProxy: config.TRUST_PROXY,
    bodyLimit: 1024 * 1024,
  });

  app.decorate("config", config);

  /*
   * 备份路由需要知道**实际**使用的库路径。
   * config.DATABASE_PATH 只是默认值，可能被 options 覆盖
   * （测试、多实例部署都会这么用）。备份/恢复照着 config 走
   * 会操作到错误的文件。
   */
  app.decorate("databasePath", resolvedDatabasePath);

  /*
   * 数据库句柄用**可变容器**持有，而不是直接 decorate 实例本身。
   *
   * 原因：Fastify 的 decorate 是一次性写入，之后改写
   * app.db = ... 会抛 "already been added" 或静默失效。
   * 而恢复备份时整个数据库文件被替换，所有引用都必须指向新连接 ——
   * 用一个可变的 holder 就能让所有持有者自然看到新值。
   */
  const holder: { value: NodeDatabase } = { value: db };
  Object.defineProperty(app, "db", {
    get: () => holder.value.db,
    configurable: true,
  });

  app.decorate("database", {
    get raw() {
      return holder.value.raw;
    },
    close: () => holder.value.close(),
  });

  app.decorate("reopenDatabase", () => {
    holder.value = createNodeDatabase(resolvedDatabasePath);
  });

  const authHolder: { value: AuthService } = { value: new AuthService(db.db, config) };
  Object.defineProperty(app, "authService", {
    get: () => authHolder.value,
    configurable: true,
  });
  app.decorate("reopenAuthService", () => {
    authHolder.value = new AuthService(holder.value.db, config);
  });
  app.decorateRequest("auth");

  await app.register(cookie);
  /*
   * helmet 默认发 Cross-Origin-Resource-Policy: same-origin，
   * 会阻止浏览器/WebView 跨源读取响应体 —— 即使 CORS 头正确。
   * 桌面端（tauri://localhost）和网页端跨源访问都受此影响，
   * 表现为「请求 200 但前端拿不到数据」。
   *
   * 这里设为 cross-origin：本服务本来就是给多个客户端跨源调用的。
   * 真正的访问控制由 CORS 白名单 + 认证令牌负责，不靠 CORP。
   */
  await app.register(helmet, {
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: "cross-origin" },
    // 同理：COOP 会隔离跨源窗口引用，对我们的纯 API 无意义
    crossOriginOpenerPolicy: false,
  });

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

  /*
   * 过期会话清理。
   *
   * purgeExpiredSessions() 之前定义了却没人调用 ——
   * 会话表会随着每次登录无限增长（一年轻松上千行），
   * 既拖慢查询也浪费空间。
   *
   * 策略：启动时清一次 + 每 6 小时一次，保留 7 天宽限期
   * （宽限期让「刚过期就想不起密码」的用户还有机会排查日志）。
   */
  const PURGE_INTERVAL_MS = 6 * 60 * 60 * 1000;
  const PURGE_GRACE_MS = 7 * 24 * 60 * 60 * 1000;

  const purge = async () => {
    try {
      const removed = await purgeExpiredSessions(app.db, Date.now(), PURGE_GRACE_MS);
      if (removed > 0) app.log.info(`清理了 ${removed} 条过期会话`);
    } catch (error) {
      app.log.warn({ error }, "清理过期会话失败");
    }
  };

  // 启动时清一次（不阻塞启动）
  void purge();

  const timer = setInterval(() => void purge(), PURGE_INTERVAL_MS);
  // 不阻止进程退出
  timer.unref?.();

  app.addHook("onClose", async () => {
    clearInterval(timer);
  });

  await app.register(async (scope) => {
    await scope.register(rateLimit, {
      global: false,
      max: LOGIN_RATE_LIMIT.max,
      timeWindow: LOGIN_RATE_LIMIT.timeWindow,
    });
    await registerAuthRoutes(scope);
  });

  await registerServerRoutes(app);
  await registerBackupRoutes(app);
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
