import type { ToolCategory, ToolGroup } from "./tools.js";

export interface ToolCatalogEntry {
  id: string;
  name: string;
  description: string;
  /** 一级分组：侧栏顶层目录 */
  group: ToolGroup;
  /** 二级分类：分组下的细分目录 */
  category: ToolCategory;
  /** lucide-react 图标名，前端按名取组件 */
  icon: string;
  defaultSortOrder: number;
}

/**
 * 2.0 内置工具目录（前后端共用）。
 *
 * 两级组织：
 *   分组（group）  → 侧栏一级目录，例如「编码」
 *   分类（category）→ 分组内的二级目录，例如「数据 / 文本 / 生成」
 *
 * 目前所有内置工具都在「编码」分组下；后续接入 SSH、数据库等能力时
 * 直接新增分组即可，侧栏会自动多出一级目录。
 */
export const toolCatalog: readonly ToolCatalogEntry[] = [
  {
    id: "json-formatter",
    name: "JSON 格式化",
    description: "格式化、压缩与校验 JSON，支持路径提取。",
    group: "encode",
    category: "default",
    icon: "Braces",
    defaultSortOrder: 10,
  },
  {
    id: "base64",
    name: "Base64 编解码",
    description: "文本与 Base64 互转，支持 URL 安全字符集。",
    group: "encode",
    category: "default",
    icon: "Binary",
    defaultSortOrder: 20,
  },
  {
    id: "url-codec",
    name: "URL 编解码",
    description: "URL 编码 / 解码，支持组件与完整地址两种模式。",
    group: "encode",
    category: "default",
    icon: "Link",
    defaultSortOrder: 30,
  },
  {
    id: "timestamp",
    name: "时间戳转换",
    description: "Unix 时间戳与本地时间互转，支持毫秒与秒。",
    group: "encode",
    category: "default",
    icon: "Clock",
    defaultSortOrder: 40,
  },
  {
    id: "hash",
    name: "哈希计算",
    description: "MD5 / SHA-1 / SHA-256 摘要，纯前端计算。",
    group: "encode",
    category: "default",
    icon: "Hash",
    defaultSortOrder: 50,
  },
  {
    id: "servers",
    name: "服务器",
    description: "SSH 终端、SFTP 文件管理与系统监控。",
    group: "remote",
    category: "servers",
    icon: "Server",
    defaultSortOrder: 10,
  },
  {
    id: "uuid",
    name: "UUID 生成器",
    description: "批量生成 UUID v4，支持大写与连字符开关。",
    group: "encode",
    category: "default",
    icon: "Fingerprint",
    defaultSortOrder: 60,
  },
];

export function findTool(id: string): ToolCatalogEntry | undefined {
  return toolCatalog.find((tool) => tool.id === id);
}

/** 一级分组的显示名与排序。 */
export const toolGroupMeta: Record<ToolGroup, { label: string; order: number }> = {
  encode: { label: "编码", order: 10 },
  remote: { label: "远程", order: 20 },
  devops: { label: "运维", order: 30 },
  system: { label: "系统", order: 40 },
};

/**
 * 二级分类的显示名与排序。
 *
 * 目前只有两个有意义的值：`default` 表示「直接挂在分组下」，
 * `servers` 用于远程分组的服务器入口。侧栏会把 default 分类下的工具
 * 直接铺在分组标题下，不再渲染分类层级。
 */
export const toolCategoryMeta: Record<ToolCategory, { label: string; order: number }> = {
  default: { label: "", order: 10 },
  servers: { label: "服务器", order: 20 },
  other: { label: "其他", order: 90 },
};
