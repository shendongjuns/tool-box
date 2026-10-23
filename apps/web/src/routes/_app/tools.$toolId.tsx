import * as React from "react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowLeft } from "lucide-react";
import { findTool } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { ToolRunner } from "@/components/tools/tool-runner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/_app/tools/$toolId")({
  loader: ({ params }) => {
    const tool = findTool(params.toolId);
    if (!tool) throw notFound();
    return { tool };
  },
  component: ToolPage,
});

function ToolPage() {
  const { tool } = Route.useLoaderData();
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();

  /*
   * 打开工具时记录一次使用时间。
   *
   * 之前这个接口（POST /api/tools/:id/touch）从来没被调用过，
   * 所以 lastOpenedAt 永远是 null，仪表盘的「最近使用」拿不到数据。
   * 这里在挂载时上报，并让仪表盘缓存失效，回到首页即可看到最新记录。
   */
  React.useEffect(() => {
    let cancelled = false;
    void api
      .touchTool(tool.id)
      .then(() => {
        if (cancelled) return;
        void queryClient.invalidateQueries({ queryKey: queryKeys.dashboard(sourceKey) });
      })
      .catch(() => {
        /* 记录失败不影响工具使用 */
      });
    return () => {
      cancelled = true;
    };
  }, [api, tool.id, queryClient, sourceKey]);

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <Button variant="ghost" size="sm" asChild className="-ml-2 mb-1">
            <Link to="/dashboard">
              <ArrowLeft className="h-4 w-4" />
              返回仪表盘
            </Link>
          </Button>
          <h1 className="text-2xl font-semibold tracking-tight">{tool.name}</h1>
          <p className="mt-1 text-sm text-muted-foreground">{tool.description}</p>
        </div>
        <Badge variant="outline">{tool.id}</Badge>
      </div>

      <ToolRunner toolId={tool.id} />
    </div>
  );
}