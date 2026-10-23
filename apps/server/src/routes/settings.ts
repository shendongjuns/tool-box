import type { FastifyInstance } from "fastify";
import { putSettingsRequestSchema } from "@toolbox/contracts";
import { getSettings, putSettings } from "@toolbox/data";
import { badRequest } from "../plugins/errors.js";

/**
 * 允许写入的设置键前缀。
 *
 * 只放行 `ui.` 前缀 —— 其它前缀（例如本地数据源用的 `app.*`）属于内部状态，
 * 不允许通过公开接口写入。
 */
const ALLOWED_PREFIX = "ui.";

export async function registerSettingsRoutes(app: FastifyInstance): Promise<void> {
  app.get("/api/settings", { preHandler: app.requireAuth }, async () => getSettings(app.db));

  app.put("/api/settings", { preHandler: app.requireAuth }, async (request) => {
    const body = putSettingsRequestSchema.parse(request.body);

    for (const key of Object.keys(body.values)) {
      if (!key.startsWith(ALLOWED_PREFIX)) {
        throw badRequest("INVALID_KEY", `不支持的设置项：${key}`);
      }
    }

    return putSettings(app.db, body.values, Date.now());
  });
}
