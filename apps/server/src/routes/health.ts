import type { FastifyInstance } from "fastify";
import { sql } from "drizzle-orm";

export async function registerHealthRoutes(app: FastifyInstance): Promise<void> {
  app.get("/api/health", async (_request, reply) => {
    try {
      await app.db.run(sql`select 1`);
      return {
        status: "ok",
        version: app.config.APP_VERSION,
        uptime: Math.round(process.uptime()),
        db: "ok",
      };
    } catch (error) {
      app.log.error({ err: error }, "health check failed");
      return reply.status(503).send({ status: "degraded", db: "error" });
    }
  });
}
