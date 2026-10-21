import { z } from "zod";
import { displayNameSchema, epochMs, passwordSchema, usernameSchema } from "./common.js";

export const publicUserSchema = z.object({
  id: z.string(),
  username: z.string(),
  displayName: z.string().nullable(),
  createdAt: epochMs,
  lastLoginAt: epochMs.nullable(),
});
export type PublicUser = z.infer<typeof publicUserSchema>;

export const sessionKindSchema = z.enum(["web", "desktop", "local"]);
export type SessionKind = z.infer<typeof sessionKindSchema>;

export const sessionInfoSchema = z.object({
  expiresAt: epochMs,
  createdAt: epochMs,
  lastUsedAt: epochMs,
  kind: sessionKindSchema,
});
export type SessionInfo = z.infer<typeof sessionInfoSchema>;

export const sessionDeviceSchema = z.object({
  id: z.string(),
  kind: sessionKindSchema,
  deviceName: z.string().nullable(),
  userAgent: z.string().nullable(),
  ip: z.string().nullable(),
  createdAt: epochMs,
  lastUsedAt: epochMs,
  expiresAt: epochMs,
  current: z.boolean(),
});
export type SessionDevice = z.infer<typeof sessionDeviceSchema>;

/**
 * 初始化状态。
 *
 * 单用户系统：`initialized === false` 表示库里一个用户都没有，
 * 此时登录页会切换成「创建管理员」表单；注册成功后永远返回 true，
 * 不再提供任何创建用户的入口。
 */
export const bootstrapStatusSchema = z.object({
  initialized: z.boolean(),
  /** 已注册的管理员用户名，仅 initialized 时有值，用于登录页提示 */
  username: z.string().nullable(),
});
export type BootstrapStatus = z.infer<typeof bootstrapStatusSchema>;

export const bootstrapRequestSchema = z.object({
  username: usernameSchema,
  password: passwordSchema,
  displayName: displayNameSchema,
});
export type BootstrapRequest = z.infer<typeof bootstrapRequestSchema>;

export const loginRequestSchema = z.object({
  username: usernameSchema,
  password: z.string().min(1).max(128),
  deviceName: z.string().trim().max(64).optional(),
});
export type LoginRequest = z.infer<typeof loginRequestSchema>;

/** 桌面端登录额外返回令牌（网页端走 Cookie，不返回） */
export const desktopLoginResponseSchema = z.object({
  token: z.string(),
  expiresAt: epochMs,
  user: publicUserSchema,
});
export type DesktopLoginResponse = z.infer<typeof desktopLoginResponseSchema>;

export const loginResponseSchema = z.object({
  user: publicUserSchema,
  session: sessionInfoSchema,
  /** 仅桌面端（kind=desktop）返回 */
  token: z.string().optional(),
});
export type LoginResponse = z.infer<typeof loginResponseSchema>;

export const meResponseSchema = z.object({
  user: publicUserSchema,
  session: sessionInfoSchema,
});
export type MeResponse = z.infer<typeof meResponseSchema>;

export const changePasswordRequestSchema = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: passwordSchema,
});
export type ChangePasswordRequest = z.infer<typeof changePasswordRequestSchema>;

export const sessionListResponseSchema = z.object({
  items: z.array(sessionDeviceSchema),
});
export type SessionListResponse = z.infer<typeof sessionListResponseSchema>;
