import { z } from "zod";
import { epochMs } from "./common.js";

export const themeModeSchema = z.enum(["light", "dark", "system"]);
export type ThemeMode = z.infer<typeof themeModeSchema>;

export const accentSchema = z.enum(["indigo", "violet", "emerald", "amber", "rose", "slate"]);
export type Accent = z.infer<typeof accentSchema>;

/** 全部设置项的默认值（服务端与前端共用） */
export const defaultSettings = {
  "ui.themeMode": "system",
  "ui.accent": "indigo",
  "ui.sidebarWidth": 260,
  "ui.sidebarCollapsed": false,
  "ui.closeBehavior": "ask",
  "ui.language": "zh-CN",
} as const;

export type SettingKey = keyof typeof defaultSettings;

export const settingValueSchema = z.union([z.string(), z.number(), z.boolean()]);
export type SettingValue = z.infer<typeof settingValueSchema>;

export const settingsRecordSchema = z.record(z.string(), settingValueSchema);
export type SettingsRecord = z.infer<typeof settingsRecordSchema>;

export const getSettingsResponseSchema = z.object({
  values: settingsRecordSchema,
  updatedAt: epochMs.nullable(),
});
export type GetSettingsResponse = z.infer<typeof getSettingsResponseSchema>;

export const putSettingsRequestSchema = z.object({
  values: settingsRecordSchema,
});
export type PutSettingsRequest = z.infer<typeof putSettingsRequestSchema>;
