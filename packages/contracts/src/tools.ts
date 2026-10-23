import { z } from "zod";
import { epochMs } from "./common.js";

/**
 * 一级分组（导航目录）。
 *
 * 目前所有内置工具都属于「编码」，后续接入 SSH / 数据库等能力时
 * 再增加新的分组，侧栏会按分组渲染。
 */
export const toolGroupSchema = z.enum(["encode", "devops", "system"]);
export type ToolGroup = z.infer<typeof toolGroupSchema>;

/**
 * 二级分类（分组下的细分目录）。
 *
 * 例如「编码」分组下有 数据 / 文本 / 生成 三个子类。
 */
export const toolCategorySchema = z.enum([
  "format",
  "convert",
  "generate",
  "crypto",
  "network",
  "database",
  "other",
]);
export type ToolCategory = z.infer<typeof toolCategorySchema>;

export const toolDescriptorSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string(),
  group: toolGroupSchema,
  category: toolCategorySchema,
  icon: z.string(),
  pinned: z.boolean(),
  sortOrder: z.number().int(),
  lastOpenedAt: epochMs.nullable(),
});
export type ToolDescriptor = z.infer<typeof toolDescriptorSchema>;

export const toolListResponseSchema = z.object({
  items: z.array(toolDescriptorSchema),
});
export type ToolListResponse = z.infer<typeof toolListResponseSchema>;

export const patchToolRequestSchema = z.object({
  pinned: z.boolean().optional(),
  // 排序值限制在 [0, 1000]：防止用户写 -99999 / 99999 破坏列表顺序
  sortOrder: z.number().int().min(0).max(1000).optional(),
});
export type PatchToolRequest = z.infer<typeof patchToolRequestSchema>;