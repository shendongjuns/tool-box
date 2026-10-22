import { z } from "zod";

/** 统一错误体 */
export const apiErrorSchema = z.object({
  code: z.string(),
  message: z.string(),
  details: z.unknown().optional(),
});
export type ApiError = z.infer<typeof apiErrorSchema>;

/** 统一成功包装（列表类接口用） */
export const okSchema = z.object({ ok: z.literal(true) });

/** ISO 时间戳（毫秒） */
export const epochMs = z.number().int().nonnegative();

/** 用户名规则：3-32 位字母/数字/下划线/连字符 */
export const usernameSchema = z
  .string()
  .trim()
  .min(3, "用户名至少 3 个字符")
  .max(32, "用户名最多 32 个字符")
  .regex(/^[a-zA-Z0-9_-]+$/, "仅允许字母、数字、下划线与连字符");

/**
 * 密码规则：**不做任何强度/长度限制**。
 *
 * 只要求非空 —— 空密码会让「密码校验」退化为「只验用户名」，
 * 那才是真正的风险。除此之外，一位数字、一句话都可以。
 */
export const passwordSchema = z.string().min(1, "密码不能为空");

export const displayNameSchema = z.string().trim().min(1).max(48).optional();
