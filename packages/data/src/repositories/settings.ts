import { asc, eq } from "drizzle-orm";
import { type SettingValue, type SettingsRecord } from "@toolbox/contracts";
import { settings } from "../schema.js";
import type { AppDatabase } from "../types.js";

function encode(value: SettingValue): string {
  return JSON.stringify(value);
}

function decode(raw: string): SettingValue | undefined {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed === "string" || typeof parsed === "number" || typeof parsed === "boolean") {
      return parsed;
    }
    return undefined;
  } catch {
    return undefined;
  }
}

/**
 * 读取全部设置。
 *
 * 只返回**库中真实存在**的键 —— 不合并 defaultSettings。
 * 合并会让「用户从未设置过 X」与「用户把 X 设成默认值」无法区分，
 * 而且前端会把默认键当成服务器值重新应用，覆盖本地未保存的修改。
 * 缺省值由前端在键缺失时兜底。
 */
export async function getSettings(db: AppDatabase): Promise<{
  values: SettingsRecord;
  updatedAt: number | null;
}> {
  const rows = await db.select().from(settings).orderBy(asc(settings.key));
  const values: SettingsRecord = {};
  let updatedAt: number | null = null;
  for (const row of rows) {
    const value = decode(row.value);
    if (value === undefined) continue;
    values[row.key] = value;
    if (updatedAt === null || row.updatedAt > updatedAt) updatedAt = row.updatedAt;
  }
  return { values, updatedAt };
}

/** 合并写入（只覆盖请求里出现的键），单事务完成。 */
export async function putSettings(
  db: AppDatabase,
  values: SettingsRecord,
  now: number,
): Promise<{ values: SettingsRecord; updatedAt: number }> {
  for (const [key, value] of Object.entries(values)) {
    await db
      .insert(settings)
      .values({ key, value: encode(value), updatedAt: now })
      .onConflictDoUpdate({
        target: settings.key,
        set: { value: encode(value), updatedAt: now },
      });
  }
  const next = await getSettings(db);
  return { values: next.values, updatedAt: now };
}

/** 单键读取，供前端主题等场景使用。 */
export async function getSetting(db: AppDatabase, key: string): Promise<SettingValue | undefined> {
  const rows = await db.select().from(settings).where(eq(settings.key, key)).limit(1);
  const row = rows[0];
  return row ? decode(row.value) : undefined;
}