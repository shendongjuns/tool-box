import * as React from "react";
import { createRootRouteWithContext, Outlet } from "@tanstack/react-router";
import type { QueryClient } from "@tanstack/react-query";
import { ApiProvider } from "@/lib/api-context";
import { ErrorBoundary } from "@/components/error-boundary";
import { installGlobalErrorHandlers } from "@/lib/global-errors";

export interface RouterContext {
  queryClient: QueryClient;
}

export const Route = createRootRouteWithContext<RouterContext>()({
  component: RootComponent,
});

function RootComponent() {
  /*
   * 全局未捕获异常 → 可见提示（避免「点了没反应」这种无声失败）。
   * 放在 effect 里：渲染期不应有副作用，且 effect 天然处理了
   * StrictMode 的「挂载-卸载-再挂载」。
   */
  React.useEffect(() => installGlobalErrorHandlers(), []);

  return (
    <ErrorBoundary>
      <ApiProvider>
        <div className="min-h-screen bg-background text-foreground">
          <Outlet />
        </div>
      </ApiProvider>
    </ErrorBoundary>
  );
}
