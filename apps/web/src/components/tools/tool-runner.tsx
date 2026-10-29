import * as React from "react";
import type { ComponentType } from "react";
import { JsonFormatterTool } from "@/features/tools/json-formatter";
import { Base64Tool } from "@/features/tools/base64";
import { UrlCodecTool } from "@/features/tools/url-codec";
import { TimestampTool } from "@/features/tools/timestamp";
import { HashTool } from "@/features/tools/hash";
import { UuidTool } from "@/features/tools/uuid";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

/*
 * 服务器工具单独懒加载。
 *
 * 它带着 xterm（终端）与 visx（图表）两个重依赖，合计约 300KB。
 * 这两个库只有真正打开 SSH 终端/监控时才用得上，
 * 静态打包进来会让首屏多下载一大截。
 *
 * 其余六个编码工具都很轻（各自几 KB），保持静态导入 ——
 * 懒加载它们只会多出几次网络往返，反而更慢。
 */
const RemotePage = React.lazy(() =>
  import("@/features/remote/remote-page").then((module) => ({ default: module.RemotePage })),
);

const registry: Record<string, ComponentType> = {
  "json-formatter": JsonFormatterTool,
  base64: Base64Tool,
  "url-codec": UrlCodecTool,
  timestamp: TimestampTool,
  hash: HashTool,
  uuid: UuidTool,
  servers: RemotePage,
};

/** 需要 Suspense 包裹的懒加载工具。 */
const LAZY = new Set(["servers"]);

/** 需要整页宽度、不能包在卡片里的工具。 */
const FULL_BLEED = new Set(["servers"]);

export function ToolRunner({ toolId }: { toolId: string }) {
  const Component = registry[toolId];

  if (Component && FULL_BLEED.has(toolId)) {
    const content = <Component />;
    return LAZY.has(toolId) ? (
      <React.Suspense fallback={<ToolLoading />}>{content}</React.Suspense>
    ) : (
      content
    );
  }

  if (!Component) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-sm text-muted-foreground">
          该工具尚未实现。
        </CardContent>
      </Card>
    );
  }

  const content = <Component />;
  return LAZY.has(toolId) ? (
    <React.Suspense fallback={<ToolLoading />}>{content}</React.Suspense>
  ) : (
    content
  );
}

/** 懒加载工具的占位：骨架屏，避免切换时白屏跳动。 */
function ToolLoading() {
  return (
    <div className="space-y-3">
      <Skeleton className="h-8 w-48" />
      <Skeleton className="h-24 w-full" />
      <Skeleton className="h-24 w-full" />
    </div>
  );
}
