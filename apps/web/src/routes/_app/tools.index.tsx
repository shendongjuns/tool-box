import { createFileRoute, Link } from "@tanstack/react-router";
import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Pin, PinOff } from "lucide-react";
import { toolCatalog } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { cn } from "@/lib/utils";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/_app/tools/")({
  component: ToolsPage,
});

const categoryLabels: Record<string, string> = {
  work: "工作",
  data: "数据处理",
  database: "数据库",
  text: "文本",
  encode: "编解码",
  system: "系统",
  other: "其他",
};

/** 工具列表：支持置顶常用工具。 */
function ToolsPage() {
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();

  const tools = useQuery({
    queryKey: queryKeys.tools(sourceKey),
    queryFn: () => api.listTools(),
  });

  const togglePin = useMutation({
    mutationFn: ({ id, pinned }: { id: string; pinned: boolean }) =>
      api.patchTool(id, { pinned }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: queryKeys.tools(sourceKey) });
      void queryClient.invalidateQueries({ queryKey: queryKeys.dashboard(sourceKey) });
    },
  });

  // 置顶优先，其次按目录顺序
  const sorted = React.useMemo(() => {
    const byId = new Map((tools.data?.items ?? []).map((item) => [item.id, item]));
    const list = toolCatalog.map((tool) => {
      const state = byId.get(tool.id);
      return {
        ...tool,
        pinned: state?.pinned ?? false,
        sortOrder: state?.sortOrder ?? tool.defaultSortOrder,
      };
    });
    return list.sort((a, b) => {
      if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
      return a.sortOrder - b.sortOrder;
    });
  }, [tools.data]);

  const groups = React.useMemo(() => {
    const pinned = sorted.filter((tool) => tool.pinned);
    const rest = sorted.filter((tool) => !tool.pinned);
    const map = new Map<string, typeof sorted>();
    for (const tool of rest) {
      const bucket = map.get(tool.category) ?? [];
      bucket.push(tool);
      map.set(tool.category, bucket);
    }
    return { pinned, groups: [...map.entries()] };
  }, [sorted]);

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">全部工具</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {toolCatalog.length} 个内置工具 · 可置顶常用项
        </p>
      </header>

      {groups.pinned.length > 0 ? (
        <section className="space-y-2">
          <h2 className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
            <Pin className="h-3 w-3" />
            置顶
          </h2>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {groups.pinned.map((tool) => (
              <ToolTile
                key={tool.id}
                tool={tool}
                pinned
                onTogglePin={() => togglePin.mutate({ id: tool.id, pinned: false })}
              />
            ))}
          </div>
        </section>
      ) : null}

      {groups.groups.map(([category, list]) => (
        <section key={category} className="space-y-2">
          <h2 className="text-xs font-medium text-muted-foreground">
            {categoryLabels[category] ?? category}
          </h2>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {list.map((tool) => (
              <ToolTile
                key={tool.id}
                tool={tool}
                onTogglePin={() => togglePin.mutate({ id: tool.id, pinned: true })}
              />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

function ToolTile({
  tool,
  pinned = false,
  onTogglePin,
}: {
  tool: { id: string; name: string; description: string };
  pinned?: boolean;
  onTogglePin: () => void;
}) {
  return (
    <Card className={cn("group relative transition-colors hover:border-border", pinned && "border-primary/30")}>
      <CardContent className="p-3">
        <Link to="/tools/$toolId" params={{ toolId: tool.id }} className="block pr-6">
          <p className="text-sm font-medium">{tool.name}</p>
          <p className="mt-0.5 line-clamp-1 text-xs text-muted-foreground">{tool.description}</p>
        </Link>
        <Button
          variant="ghost"
          size="icon"
          onClick={onTogglePin}
          title={pinned ? "取消置顶" : "置顶"}
          className={cn(
            "absolute right-1.5 top-1.5 h-7 w-7",
            pinned
              ? "text-primary opacity-100"
              : "text-muted-foreground opacity-0 group-hover:opacity-100 focus:opacity-100",
          )}
        >
          {pinned ? <Pin className="h-3.5 w-3.5" /> : <PinOff className="h-3.5 w-3.5" />}
        </Button>
      </CardContent>
    </Card>
  );
}