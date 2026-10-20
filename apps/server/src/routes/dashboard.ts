import type { FastifyInstance } from "fastify";
import { buildDashboard } from "@toolbox/data";
import { unauthorized } from "../plugins/errors.js";

export async function registerDashboardRoutes(app: FastifyInstance): Promise<void> {
  app.get("/api/dashboard", { preHandler: app.requireAuth }, async (request) => {
    const auth = request.auth;
    if (!auth) throw unauthorized();
    return buildDashboard(app.db, {
      version: app.config.APP_VERSION,
      uptimeSeconds: Math.round(process.uptime()),
      userId: auth.user.id,
      now: Date.now(),
    });
  });
}
