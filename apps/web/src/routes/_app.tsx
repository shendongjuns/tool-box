import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { ApiError } from "@toolbox/api-client";
import { getApi } from "@/lib/api-context";
import { useAuth } from "@/lib/auth-session";
import { AppShell } from "@/components/shell/app-shell";

export const Route = createFileRoute("/_app")({
  beforeLoad: async () => {
    try {
      const me = await getApi().me();
      useAuth.getState().setAuth({ user: me.user, session: me.session });
    } catch (error) {
      useAuth.getState().setAuth(null);

      // 只有「确实没登录」或「完全连不上」才跳登录页；
      // 其它错误交给页面内提示，避免误判成掉登录。
      if (error instanceof ApiError && (error.status === 401 || error.isNetworkError)) {
        throw redirect({ to: "/login" });
      }
      throw error;
    }
  },
  component: AppLayout,
});

function AppLayout() {
  return (
    <AppShell>
      <Outlet />
    </AppShell>
  );
}
