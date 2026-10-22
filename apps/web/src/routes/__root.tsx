import { createRootRouteWithContext, Outlet } from "@tanstack/react-router";
import type { QueryClient } from "@tanstack/react-query";
import { ApiProvider } from "@/lib/api-context";

export interface RouterContext {
  queryClient: QueryClient;
}

export const Route = createRootRouteWithContext<RouterContext>()({
  component: RootComponent,
});

function RootComponent() {
  return (
    <ApiProvider>
      <div className="min-h-screen bg-background text-foreground">
        <Outlet />
      </div>
    </ApiProvider>
  );
}