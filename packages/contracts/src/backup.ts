import { z } from "zod";
import { epochMs } from "./common.js";

/**
 * 备份文件。
 *
 * 文件名形如 `local.db.v2-2026-11-02T11-30-00.bak`：
 * 库名 + schema 版本 + 创建时间。版本号让人一眼看出
 * 这份备份来自哪个结构，避免把高版本数据恢复到低版本程序上。
 */
export const backupFileSchema = z.object({
  name: z.string(),
  size: z.number().int().nonnegative(),
  createdAt: epochMs,
  version: z.number().int().nonnegative(),
});
export type BackupFile = z.infer<typeof backupFileSchema>;

export const listBackupsResponseSchema = z.object({
  files: z.array(backupFileSchema),
  /** 全部备份合计字节数，用于界面显示 */
  totalSize: z.number().int().nonnegative(),
  /** 数据库文件本身的大小 */
  databaseSize: z.number().int().nonnegative(),
  /** 当前 schema 版本 */
  schemaVersion: z.number().int().nonnegative(),
});
export type ListBackupsResponse = z.infer<typeof listBackupsResponseSchema>;

/**
 * 恢复请求。
 *
 * name 用白名单正则约束：只允许字母数字、点、横线、下划线，
 * 且必须以 .bak 结尾 —— 杜绝 ../ 之类的路径穿越。
 */
export const restoreBackupRequestSchema = z.object({
  name: z.string().regex(/^[\w.-]+\.v\d+-[\dT-]+(?:-\d+)?\.bak$/, "备份文件名不合法"),
});
export type RestoreBackupRequest = z.infer<typeof restoreBackupRequestSchema>;

export const restoreBackupResponseSchema = z.object({
  ok: z.literal(true),
  /** 恢复前自动生成的当前数据副本 */
  safetyCopy: z.string(),
  /** 恢复后需要重新登录 */
  requiresRelogin: z.literal(true),
});
export type RestoreBackupResponse = z.infer<typeof restoreBackupResponseSchema>;

export const createBackupResponseSchema = z.object({
  file: backupFileSchema,
});
export type CreateBackupResponse = z.infer<typeof createBackupResponseSchema>;

export const deleteBackupResponseSchema = z.object({
  ok: z.literal(true),
});
export type DeleteBackupResponse = z.infer<typeof deleteBackupResponseSchema>;
