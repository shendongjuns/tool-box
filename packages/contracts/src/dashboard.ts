import { z } from "zod";
import { epochMs } from "./common.js";
import { toolDescriptorSchema } from "./tools.js";

export const dashboardStatsSchema = z.object({
  totalTools: z.number().int(),
  pinnedTools: z.number().int(),
  activeSessions: z.number().int(),
  settingsCount: z.number().int(),
});
export type DashboardStats = z.infer<typeof dashboardStatsSchema>;

export const dashboardResponseSchema = z.object({
  stats: dashboardStatsSchema,
  recentTools: z.array(toolDescriptorSchema),
  lastActiveAt: epochMs.nullable(),
  server: z.object({
    version: z.string(),
    uptime: z.number(),
    dataSource: z.literal("cloud"),
  }),
});
export type DashboardResponse = z.infer<typeof dashboardResponseSchema>;
