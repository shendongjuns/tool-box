import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { patchToolRequestSchema } from "@toolbox/contracts";
import { listTools, patchTool, touchTool } from "@toolbox/data";
import { notFound } from "../plugins/errors.js";

const paramsSchema = z.object({ id: z.string().min(1) });

export async function registerToolsRoutes(app: FastifyInstance): Promise<void> {
  app.get("/api/tools", { preHandler: app.requireAuth }, async () => ({
    items: await listTools(app.db),
  }));

  app.patch("/api/tools/:id", { preHandler: app.requireAuth }, async (request) => {
    const { id } = paramsSchema.parse(request.params);
    const patch = patchToolRequestSchema.parse(request.body);
    const ok = await patchTool(app.db, id, patch, Date.now());
    if (!ok) throw notFound("工具不存在");
    return { items: await listTools(app.db) };
  });

  app.post("/api/tools/:id/touch", { preHandler: app.requireAuth }, async (request) => {
    const { id } = paramsSchema.parse(request.params);
    await touchTool(app.db, id, Date.now());
    return { ok: true };
  });
}
