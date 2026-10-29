import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import {
  bootstrapRequestSchema,
  changePasswordRequestSchema,
  loginRequestSchema,
  sessionListResponseSchema,
  type SessionKind,
} from "@toolbox/contracts";
import { listSessions, revokeSession, revokeUserSessions, touchSession } from "@toolbox/data";
import { hashPassword, verifyPassword } from "../auth/password.js";
import { toPublicUser } from "../auth/service.js";
import { ApiError, conflict, notFound, unauthorized } from "../plugins/errors.js";

const sessionParamsSchema = z.object({ id: z.string().min(1) });

/** 桌面端会带 X-Toolbox-Client: desktop，据此区分会话类型并返回 Bearer 令牌。 */
function sessionKindFor(request: FastifyRequest): SessionKind {
  return request.headers["x-toolbox-client"] === "desktop" ? "desktop" : "web";
}

function loginMeta(request: FastifyRequest, deviceName?: string) {
  return {
    kind: sessionKindFor(request),
    deviceName: deviceName ?? null,
    userAgent: request.headers["user-agent"] ?? null,
    ip: request.ip,
  };
}

export async function registerAuthRoutes(app: FastifyInstance): Promise<void> {
  const { config, authService } = app;

  const setSessionCookie = (reply: FastifyReply, token: string) => {
    reply.setCookie(config.cookieName, token, {
      httpOnly: true,
      sameSite: "lax",
      // secure: "auto" —— 经反向代理转发 HTTPS 时自动加 Secure，纯 HTTP 也能用
      secure: "auto",
      path: "/",
      maxAge: Math.floor(config.sessionTtlMs / 1000),
    });
  };

  /**
   * 初始化状态。
   *
   * `initialized: false` 表示数据库里一个用户都没有 —— 前端据此把登录页
   * 切换成「创建管理员」。只要注册成功过一次，这里永远是 true，
   * 系统里不会再出现任何创建用户的入口。
   */
  app.get("/api/auth/bootstrap", async () => {
    const initialized = await authService.isInitialized();
    const owner = initialized ? await authService.findOwner() : undefined;
    return {
      initialized,
      username: owner?.username ?? null,
      // 服务端（网页端 / 云端）永远要求账号密码
      authMode: "password",
    };
  });

  /** 创建唯一管理员：仅当 users 为空时成功，并发下也只有一次能成功。 */
  app.post(
    "/api/auth/bootstrap",
    { config: { rateLimit: { max: 5, timeWindow: "1 minute" } } },
    async (request, reply) => {
      const body = bootstrapRequestSchema.parse(request.body);

      if (await authService.isInitialized()) {
        throw conflict("ALREADY_INITIALIZED", "管理员已创建，请直接登录");
      }

      const passwordHash = await hashPassword(body.password);
      let user;
      try {
        user = await authService.createFirstUser({
          username: body.username,
          passwordHash,
          displayName: body.displayName ?? body.username,
        });
      } catch (error) {
        // 并发注册时唯一约束会抛错，统一转成 409
        if (String(error).includes("UNIQUE")) {
          throw conflict("ALREADY_INITIALIZED", "管理员已创建，请直接登录");
        }
        throw error;
      }

      const now = Date.now();
      const session = await authService.issueSession(user.id, loginMeta(request), now);
      setSessionCookie(reply, session.token);

      const kind = sessionKindFor(request);
      return reply.status(201).send({
        user: toPublicUser(user),
        session: { createdAt: now, lastUsedAt: now, expiresAt: session.expiresAt, kind },
        ...(kind === "desktop" ? { token: session.token } : {}),
      });
    },
  );

  app.post(
    "/api/auth/login",
    { config: { rateLimit: { max: 10, timeWindow: "1 minute" } } },
    async (request, reply) => {
      const body = loginRequestSchema.parse(request.body);
      const user = await authService.findByUsername(body.username);
      if (!user || !(await verifyPassword(user.passwordHash, body.password))) {
        throw unauthorized("用户名或密码不正确");
      }

      const now = Date.now();
      await authService.markLogin(user.id, now);
      const session = await authService.issueSession(
        user.id,
        loginMeta(request, body.deviceName),
        now,
      );
      setSessionCookie(reply, session.token);

      const kind = sessionKindFor(request);
      return {
        user: toPublicUser({ ...user, lastLoginAt: now }),
        session: { createdAt: now, lastUsedAt: now, expiresAt: session.expiresAt, kind },
        ...(kind === "desktop" ? { token: session.token } : {}),
      };
    },
  );

  /** 桌面端专用：不写 Cookie，直接返回 Bearer 令牌。 */
  app.post(
    "/api/auth/desktop-login",
    { config: { rateLimit: { max: 10, timeWindow: "1 minute" } } },
    async (request) => {
      const body = loginRequestSchema.parse(request.body);
      const user = await authService.findByUsername(body.username);
      if (!user || !(await verifyPassword(user.passwordHash, body.password))) {
        throw unauthorized("用户名或密码不正确");
      }

      const now = Date.now();
      await authService.markLogin(user.id, now);
      const session = await authService.issueSession(
        user.id,
        {
          kind: "desktop",
          deviceName: body.deviceName ?? null,
          userAgent: request.headers["user-agent"] ?? null,
          ip: request.ip,
        },
        now,
      );
      return {
        token: session.token,
        expiresAt: session.expiresAt,
        user: toPublicUser({ ...user, lastLoginAt: now }),
      };
    },
  );

  app.post("/api/auth/logout", { preHandler: app.requireAuth }, async (request, reply) => {
    if (request.auth) await revokeSession(app.db, request.auth.sessionId, Date.now());
    reply.clearCookie(config.cookieName, { path: "/" });
    return reply.status(204).send();
  });

  app.get("/api/auth/me", { preHandler: app.requireAuth }, async (request) => {
    const auth = request.auth;
    if (!auth) throw unauthorized();
    return {
      user: toPublicUser(auth.user),
      session: {
        createdAt: auth.user.createdAt,
        lastUsedAt: Date.now(),
        expiresAt: auth.expiresAt,
        kind: auth.kind,
      },
    };
  });

  app.post("/api/auth/password", { preHandler: app.requireAuth }, async (request, reply) => {
    const auth = request.auth;
    if (!auth) throw unauthorized();
    const body = changePasswordRequestSchema.parse(request.body);

    if (!(await verifyPassword(auth.user.passwordHash, body.currentPassword))) {
      throw new ApiError(400, "PASSWORD_MISMATCH", "当前密码不正确");
    }

    const now = Date.now();
    await authService.changePassword(auth.user.id, await hashPassword(body.newPassword), now);
    // 改密后撤销其他设备，保留当前会话
    await revokeUserSessions(app.db, auth.user.id, now, auth.sessionId);
    // 保留当前会话的同时把它的有效期重新算满 30 天 ——
    // 否则改密时如果当前会话已接近过期，用户会被立刻踢出，
    // 与「保留当前会话」的语义矛盾。
    await touchSession(app.db, auth.sessionId, now, config.sessionTtlMs);
    return reply.status(204).send();
  });

  app.get("/api/auth/sessions", { preHandler: app.requireAuth }, async (request) => {
    const auth = request.auth;
    if (!auth) throw unauthorized();
    const rows = await listSessions(app.db, auth.user.id);
    return sessionListResponseSchema.parse({
      items: rows
        .filter((row) => row.revokedAt === null)
        .sort((a, b) => b.lastUsedAt - a.lastUsedAt)
        .map((row) => ({
          id: row.id,
          kind: row.kind,
          deviceName: row.deviceName,
          userAgent: row.userAgent,
          ip: row.ip,
          createdAt: row.createdAt,
          lastUsedAt: row.lastUsedAt,
          expiresAt: row.expiresAt,
          current: row.id === auth.sessionId,
        })),
    });
  });

  app.delete("/api/auth/sessions/:id", { preHandler: app.requireAuth }, async (request, reply) => {
    const auth = request.auth;
    if (!auth) throw unauthorized();
    const { id } = sessionParamsSchema.parse(request.params);
    // 只能下线自己的会话：先查归属，不属于当前用户一律当不存在处理
    const rows = await listSessions(app.db, auth.user.id);
    const own = rows.find((row) => row.id === id);
    if (!own) throw notFound();
    await revokeSession(app.db, id, Date.now());
    return reply.status(204).send();
  });

  app.post(
    "/api/auth/sessions/revoke-all",
    { preHandler: app.requireAuth },
    async (request, reply) => {
      const auth = request.auth;
      if (!auth) throw unauthorized();
      await revokeUserSessions(app.db, auth.user.id, Date.now(), auth.sessionId);
      return reply.status(204).send();
    },
  );
}
