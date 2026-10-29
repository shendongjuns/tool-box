import { and, count, eq, gt, isNull, max } from "drizzle-orm";
import type { DashboardResponse } from "@toolbox/contracts";
import { sessions, settings } from "../schema.js";
import { listTools, recentTools } from "./tools.js";
import type { AppDatabase } from "../types.js";

export async function buildDashboard(
  db: AppDatabase,
  meta: { version: string; uptimeSeconds: number; userId: string; now: number },
): Promise<DashboardResponse> {
  const [allTools, recent, sessionRows, settingRows, lastActive] = await Promise.all([
    listTools(db),
    recentTools(db, 4),
    db
      .select({ value: count() })
      .from(sessions)
      .where(
        and(
          eq(sessions.userId, meta.userId),
          isNull(sessions.revokedAt),
          gt(sessions.expiresAt, meta.now),
        ),
      ),
    db.select({ value: count() }).from(settings),
    db
      .select({ value: max(sessions.lastUsedAt) })
      .from(sessions)
      .where(eq(sessions.userId, meta.userId)),
  ]);

  return {
    stats: {
      totalTools: allTools.length,
      pinnedTools: allTools.filter((tool) => tool.pinned).length,
      activeSessions: sessionRows[0]?.value ?? 0,
      settingsCount: settingRows[0]?.value ?? 0,
    },
    /*
     * 只返回真正有使用记录的工具。
     * 以前没记录时会退化成「前 4 个工具」，前端就会显示一堆
     * 「尚未打开」的条目冒充最近使用 —— 这属于数据说谎。
     * 空列表让前端展示明确的空状态。
     */
    recentTools: recent,
    lastActiveAt: lastActive[0]?.value ?? null,
    server: {
      version: meta.version,
      uptime: meta.uptimeSeconds,
      dataSource: "cloud",
    },
  };
}