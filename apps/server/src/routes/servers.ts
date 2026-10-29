import type { FastifyInstance } from "fastify";
import { z } from "zod";
import {
  createServerRequestSchema,
  serverListResponseSchema,
  updateServerRequestSchema,
  type Server,
} from "@toolbox/contracts";
import {
  createServer,
  deleteServer,
  findServer,
  listServers,
  touchServerConnection,
  updateServer,
  type ServerRow,
} from "@toolbox/data";
import { notFound, unauthorized } from "../plugins/errors.js";
import { decryptCredential, encryptCredential } from "../credential.js";

const paramsSchema = z.object({ id: z.string().min(1) });

/** 转成对外 DTO：绝不回传凭据内容，只说明是否存在。 */
function toPublic(row: ServerRow): Server {
  return {
    id: row.id,
    name: row.name,
    host: row.host,
    port: row.port,
    username: row.username,
    authType: row.authType,
    hasCredential: Boolean(row.authType === "password" ? row.passwordCipher : row.privateKeyCipher),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    lastConnectedAt: row.lastConnectedAt,
  };
}

export async function registerServerRoutes(app: FastifyInstance): Promise<void> {
  app.get("/api/servers", { preHandler: app.requireAuth }, async (request) => {
    if (!request.auth) throw unauthorized();
    const rows = await listServers(app.db);
    return serverListResponseSchema.parse({ items: rows.map(toPublic) });
  });

  app.post("/api/servers", { preHandler: app.requireAuth }, async (request, reply) => {
    if (!request.auth) throw unauthorized();
    const body = createServerRequestSchema.parse(request.body);
    const now = Date.now();

    const row = await createServer(app.db, {
      id: `srv-${now.toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
      name: body.name,
      host: body.host,
      port: body.port,
      username: body.username,
      authType: body.authType,
      passwordCipher: encryptCredential(body.password),
      privateKeyCipher: encryptCredential(body.privateKey),
      passphraseCipher: encryptCredential(body.passphrase),
      now,
    });

    return reply.status(201).send(toPublic(row));
  });

  app.put("/api/servers/:id", { preHandler: app.requireAuth }, async (request) => {
    if (!request.auth) throw unauthorized();
    const { id } = paramsSchema.parse(request.params);
    const body = updateServerRequestSchema.parse(request.body);

    // 凭据字段：未提供则不修改；提供空串则清除
    const patch: Parameters<typeof updateServer>[2] = {
      name: body.name,
      host: body.host,
      port: body.port,
      username: body.username,
      authType: body.authType,
    };
    if (body.password !== undefined) {
      patch.passwordCipher = encryptCredential(body.password);
    }
    if (body.privateKey !== undefined) {
      patch.privateKeyCipher = encryptCredential(body.privateKey);
    }
    if (body.passphrase !== undefined) {
      patch.passphraseCipher = encryptCredential(body.passphrase);
    }

    const ok = await updateServer(app.db, id, patch, Date.now());
    if (!ok) throw notFound("服务器不存在");

    const row = await findServer(app.db, id);
    if (!row) throw notFound("服务器不存在");
    return toPublic(row);
  });

  app.delete("/api/servers/:id", { preHandler: app.requireAuth }, async (request, reply) => {
    if (!request.auth) throw unauthorized();
    const { id } = paramsSchema.parse(request.params);
    const ok = await deleteServer(app.db, id);
    if (!ok) throw notFound("服务器不存在");
    return reply.status(204).send();
  });

  /**
   * 取连接凭据（明文，仅本次调用返回）。
   *
   * 桌面端连接前调用一次，拿到后立即用于建立 SSH 连接，不缓存。
   * 网页端目前不支持 SSH（WebView 限制），该接口仅桌面端使用。
   */
  app.post("/api/servers/:id/credential", { preHandler: app.requireAuth }, async (request) => {
    if (!request.auth) throw unauthorized();
    const { id } = paramsSchema.parse(request.params);
    const row = await findServer(app.db, id);
    if (!row) throw notFound("服务器不存在");

    await touchServerConnection(app.db, id, Date.now());

    return {
      id: row.id,
      host: row.host,
      port: row.port,
      username: row.username,
      authType: row.authType,
      password: decryptCredential(row.passwordCipher),
      privateKey: decryptCredential(row.privateKeyCipher),
      passphrase: decryptCredential(row.passphraseCipher),
    };
  });
}
