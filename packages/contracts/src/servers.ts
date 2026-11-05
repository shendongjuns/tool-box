import { z } from "zod";
import { epochMs } from "./common.js";

/** 认证方式。 */
export const serverAuthTypeSchema = z.enum(["password", "key"]);
export type ServerAuthType = z.infer<typeof serverAuthTypeSchema>;

/** 对外暴露的服务器信息（不含凭据）。 */
export const serverSchema = z.object({
  id: z.string(),
  name: z.string(),
  host: z.string(),
  port: z.number().int().min(1).max(65535),
  username: z.string(),
  authType: serverAuthTypeSchema,
  /** 是否已保存凭据（不回传内容） */
  hasCredential: z.boolean(),
  createdAt: epochMs,
  updatedAt: epochMs,
  lastConnectedAt: epochMs.nullable(),
});
export type Server = z.infer<typeof serverSchema>;

export const serverListResponseSchema = z.object({
  items: z.array(serverSchema),
});
export type ServerListResponse = z.infer<typeof serverListResponseSchema>;

const serverFields = {
  name: z.string().trim().min(1, "请填写名称").max(64),
  host: z.string().trim().min(1, "请填写主机").max(255),
  port: z.number().int().min(1).max(65535).default(22),
  username: z.string().trim().min(1, "请填写用户名").max(64),
  authType: serverAuthTypeSchema,
};

/** 新建服务器。密码/私钥为明文，写入时由服务端加密。 */
export const createServerRequestSchema = z.object({
  ...serverFields,
  password: z.string().optional(),
  privateKey: z.string().optional(),
  passphrase: z.string().optional(),
});
export type CreateServerRequest = z.infer<typeof createServerRequestSchema>;

/** 更新服务器。凭据字段留空表示不修改。 */
export const updateServerRequestSchema = z.object({
  ...serverFields,
  password: z.string().optional(),
  privateKey: z.string().optional(),
  passphrase: z.string().optional(),
});
export type UpdateServerRequest = z.infer<typeof updateServerRequestSchema>;

/** 系统监控（一次采集的完整快照）。 */
export const monitorDiskSchema = z.object({
  mount: z.string(),
  totalBytes: z.number(),
  usedBytes: z.number(),
});

export const monitorGpuSchema = z.object({
  index: z.number().int(),
  name: z.string(),
  utilPercent: z.number(),
  memUsedMiB: z.number(),
  memTotalMiB: z.number(),
  tempC: z.number(),
  powerWatts: z.number(),
});

export const monitorNpuSchema = z.object({
  index: z.number().int(),
  name: z.string(),
  aiCorePercent: z.number(),
  hbmPercent: z.number(),
  powerWatts: z.number(),
  tempC: z.number(),
  health: z.string(),
});

export const monitorProcessSchema = z.object({
  pid: z.number().int(),
  name: z.string(),
  cpuPercent: z.number(),
  memPercent: z.number(),
});

export const monitorMetricsSchema = z.object({
  timestamp: epochMs,
  cpuPercent: z.number(),
  cpuCores: z.number().int(),
  memUsedBytes: z.number(),
  memTotalBytes: z.number(),
  swapUsedBytes: z.number(),
  swapTotalBytes: z.number(),
  disks: z.array(monitorDiskSchema),
  gpus: z.array(monitorGpuSchema),
  npus: z.array(monitorNpuSchema),
  netRxBytesPerSec: z.number(),
  netTxBytesPerSec: z.number(),
  load1: z.number(),
  load5: z.number(),
  load15: z.number(),
  /** 系统已运行秒数。取不到时为 null。 */
  uptimeSeconds: z.number().nullable(),
  processes: z.array(monitorProcessSchema),
});
export type MonitorMetrics = z.infer<typeof monitorMetricsSchema>;

/** 服务器基本信息（一次性查询）。 */
export const serverInfoSchema = z.object({
  hostname: z.string(),
  os: z.string(),
  kernel: z.string(),
  cpuModel: z.string(),
  cpuCores: z.number().int(),
  memTotalKb: z.number(),
  ip: z.string(),
});
export type ServerInfo = z.infer<typeof serverInfoSchema>;
