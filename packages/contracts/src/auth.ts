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
 * 此时登录页会切换成「创建账号」表单；注册成功后永远返回 true。
 *
 * `passwordless` 只可能出现在桌面端的本地数据源：开启后无需密码即可进入，
 * 服务端（网页端 / 云端）恒为 false，始终要求密码。
 */
export const bootstrapStatusSchema = z.object({
  initialized: z.boolean(),
  /** 已注册账号的用户名，仅 initialized 时有值 */
  username: z.string().nullable(),
  /** 本地数据源是否处于「无密码模式」；服务端恒为 false */
  passwordless: z.boolean(),
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
  /** 仅桌面端（kind=desktop / local）返回 */
  token: z.string().optional(),
});
export type LoginResponse = z.infer<typeof loginResponseSchema>;

/** 切换本地数据源的访问模式（仅桌面端本地服务支持）。 */
export const localAuthModeSchema = z.enum(["none", "password"]);
export type LocalAuthMode = z.infer<typeof localAuthModeSchema>;

export const setLocalAuthModeRequestSchema = z.object({
  mode: localAuthModeSchema,
  /** mode=password 时必填：设置（或重置）本地账号密码 */
  username: usernameSchema.optional(),
  password: passwordSchema.optional(),
});
export type SetLocalAuthModeRequest = z.infer<typeof setLocalAuthModeRequestSchema>;

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
