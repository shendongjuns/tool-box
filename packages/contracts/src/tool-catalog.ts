import type { ToolCategory } from "./tools.js";

export interface ToolCatalogEntry {
  id: string;
  name: string;
  description: string;
  category: ToolCategory;
  /** lucide-react 图标名，前端按名取组件 */
  icon: string;
  defaultSortOrder: number;
}

/**
 * 2.0 内置工具目录（前后端共用）。
 *
 * 前端据此渲染侧栏与路由；服务端据此校验 PATCH /api/tools/:id 的 id 与初始化偏好。
 * 新增工具 = 在此登记 + 在 apps/web/src/features/tools/registry.tsx 提供页面组件。
 */
export const toolCatalog: readonly ToolCatalogEntry[] = [
  {
    id: "json-formatter",
    name: "JSON 格式化",
    description: "格式化、压缩与校验 JSON，支持路径提取。",
    category: "data",
    icon: "Braces",
    defaultSortOrder: 10,
  },
  {
    id: "base64",
    name: "Base64 编解码",
    description: "文本与 Base64 互转，支持 URL 安全字符集。",
    category: "encode",
    icon: "Binary",
    defaultSortOrder: 20,
  },
  {
    id: "url-codec",
    name: "URL 编解码",
    description: "URL 编码 / 解码，支持组件与完整地址两种模式。",
    category: "encode",
    icon: "Link",
    defaultSortOrder: 30,
  },
  {
    id: "timestamp",
    name: "时间戳转换",
    description: "Unix 时间戳与本地时间互转，支持毫秒与秒。",
    category: "text",
    icon: "Clock",
    defaultSortOrder: 40,
  },
  {
    id: "hash",
    name: "哈希计算",
    description: "MD5 / SHA-1 / SHA-256 摘要，纯前端计算。",
    category: "encode",
    icon: "Hash",
    defaultSortOrder: 50,
  },
  {
    id: "uuid",
    name: "UUID 生成器",
    description: "批量生成 UUID v4，支持大写与连字符开关。",
    category: "other",
    icon: "Fingerprint",
    defaultSortOrder: 60,
  },
];

export function findTool(id: string): ToolCatalogEntry | undefined {
  return toolCatalog.find((tool) => tool.id === id);
}
