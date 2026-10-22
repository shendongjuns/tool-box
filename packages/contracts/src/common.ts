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

/**
 * 用户名规则：1-32 位，**不限制字符集**（支持中文、空格以外的任意字符）。
 *
 * 用户名只用来标识账号与界面显示，不参与 URL 或文件路径，
 * 因此没有必要限制成 ASCII 标识符。
 */
export const usernameSchema = z
  .string()
  .trim()
  .min(1, "用户名不能为空")
  .max(32, "用户名最多 32 个字符");

/**
 * 密码规则：**不做任何强度/长度限制**。
 *
 * 只要求非空 —— 空密码会让「密码校验」退化为「只验用户名」，
 * 那才是真正的风险。除此之外，一位数字、一句话都可以。
 */
export const passwordSchema = z.string().min(1, "密码不能为空");

export const displayNameSchema = z.string().trim().min(1).max(48).optional();