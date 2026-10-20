import { z } from "zod";
import { epochMs } from "./common.js";

export const toolCategorySchema = z.enum([
  "work",
  "data",
  "database",
  "text",
  "encode",
  "system",
  "other",
]);
export type ToolCategory = z.infer<typeof toolCategorySchema>;

export const toolDescriptorSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string(),
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
  sortOrder: z.number().int().optional(),
});
export type PatchToolRequest = z.infer<typeof patchToolRequestSchema>;
