import { desc, eq, isNotNull } from "drizzle-orm";
import type { ToolDescriptor } from "@toolbox/contracts";
import { toolCatalog } from "@toolbox/contracts";
import { toolPrefs } from "../schema.js";
import type { AppDatabase } from "../types.js";

/**
 * 工具清单 = 静态目录 + 用户偏好。
 *
 * 目录（id/名称/分类/图标）来自 packages/contracts，前端据此渲染；
 * 服务端只负责持久化置顶、排序与最近打开时间。
 */
export async function listTools(db: AppDatabase): Promise<ToolDescriptor[]> {
  const prefs = await db.select().from(toolPrefs);
  const prefMap = new Map(prefs.map((row) => [row.toolId, row]));

  return toolCatalog
    .map((tool) => {
      const pref = prefMap.get(tool.id);
      return {
        id: tool.id,
        name: tool.name,
        description: tool.description,
        group: tool.group,
        category: tool.category,
        icon: tool.icon,
        pinned: pref?.pinned ?? false,
        sortOrder: pref?.sortOrder ?? tool.defaultSortOrder,
        lastOpenedAt: pref?.lastOpenedAt ?? null,
      } satisfies ToolDescriptor;
    })
    .sort((a, b) => {
      if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
      if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
      return a.name.localeCompare(b.name, "zh-CN");
    });
}

export async function patchTool(
  db: AppDatabase,
  toolId: string,
  patch: { pinned?: boolean; sortOrder?: number },
  now: number,
): Promise<boolean> {
  const exists = toolCatalog.some((tool) => tool.id === toolId);
  if (!exists) return false;

  const current = await db.select().from(toolPrefs).where(eq(toolPrefs.toolId, toolId)).limit(1);
  const row = current[0];
  await db
    .insert(toolPrefs)
    .values({
      toolId,
      pinned: patch.pinned ?? row?.pinned ?? false,
      sortOrder: patch.sortOrder ?? row?.sortOrder ?? 0,
      lastOpenedAt: row?.lastOpenedAt ?? null,
      updatedAt: now,
    })
    .onConflictDoUpdate({
      target: toolPrefs.toolId,
      set: {
        pinned: patch.pinned ?? row?.pinned ?? false,
        sortOrder: patch.sortOrder ?? row?.sortOrder ?? 0,
        updatedAt: now,
      },
    });
  return true;
}

/** 记录一次工具打开（用于「最近使用」）。 */
export async function touchTool(db: AppDatabase, toolId: string, now: number): Promise<void> {
  const current = await db.select().from(toolPrefs).where(eq(toolPrefs.toolId, toolId)).limit(1);
  const row = current[0];
  await db
    .insert(toolPrefs)
    .values({
      toolId,
      pinned: row?.pinned ?? false,
      sortOrder: row?.sortOrder ?? 0,
      lastOpenedAt: now,
      updatedAt: now,
    })
    .onConflictDoUpdate({
      target: toolPrefs.toolId,
      set: { lastOpenedAt: now, updatedAt: now },
    });
}

/**
 * 最近使用过的工具。
 *
 * 必须过滤 `lastOpenedAt IS NULL`：SQLite 里 NULL 在 DESC 排序中排在最前，
 * 不过滤会把「从没打开过」的工具当成最近使用。
 */
export async function recentTools(db: AppDatabase, limit = 4): Promise<ToolDescriptor[]> {
  const rows = await db
    .select()
    .from(toolPrefs)
    .where(isNotNull(toolPrefs.lastOpenedAt))
    .orderBy(desc(toolPrefs.lastOpenedAt))
    .limit(limit);

  const all = await listTools(db);
  const byId = new Map(all.map((tool) => [tool.id, tool]));
  return rows
    .map((row) => byId.get(row.toolId))
    .filter((tool): tool is ToolDescriptor => tool !== undefined);
}