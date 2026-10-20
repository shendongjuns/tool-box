import type { FastifyInstance } from "fastify";
import { putSettingsRequestSchema } from "@toolbox/contracts";
import { getSettings, putSettings } from "@toolbox/data";

export async function registerSettingsRoutes(app: FastifyInstance): Promise<void> {
  app.get("/api/settings", { preHandler: app.requireAuth }, async () => getSettings(app.db));

  app.put("/api/settings", { preHandler: app.requireAuth }, async (request) => {
    const body = putSettingsRequestSchema.parse(request.body);
    return putSettings(app.db, body.values, Date.now());
  });
}
