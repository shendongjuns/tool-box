import * as React from "react";
import { createFileRoute, notFound } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { findTool } from "@toolbox/contracts/catalog";
import { useApi } from "@/lib/api-context";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { useToolTabs } from "@/features/tools/tool-tabs-store";

export const Route = createFileRoute("/_app/tools/$toolId")({
  loader: ({ params }) => {
    const tool = findTool(params.toolId);
    if (!tool) throw notFound();
    return { tool };
  },
  component: ToolPage,
});

/**
 * 工具页路由。
 *
 * 这个组件**不渲染工具本身** —— 工具由 <ToolWorkspace> 统一管理，
 * 所有打开过的工具都常驻挂载在那里，切换时只改 CSS 可见性。
 * 这里只负责两件事：
 * 1. 把当前路由对应的工具登记为活动标签
 * 2. 上报一次「最近打开」
 *
 * 为什么不在这里渲染：路由切换会卸载组件，工具状态（输入内容、
 * 滚动位置、图表历史）会全部丢失。常驻挂载才能保住这些。
 */
function ToolPage() {
  const { tool } = Route.useLoaderData();
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();
  const open = useToolTabs((state) => state.open);

  // 登记标签：同名工具不重复开（初步不允许多开）
  React.useEffect(() => {
    open(tool.id, tool.name);
  }, [open, tool.id, tool.name]);

  /*
   * 打开工具时记录一次使用时间。
   *
   * 之前这个接口从来没被调用过，导致 lastOpenedAt 恒为 null，
   * 仪表盘的「最近使用」拿不到数据。
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

  // 实际内容由 AppShell 里的 ToolWorkspace 渲染，这里留空
  return null;
}