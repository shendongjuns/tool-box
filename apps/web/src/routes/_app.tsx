import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { getApi } from "@/lib/api-context";
import { useAuth } from "@/lib/auth-session";
import { AppShell } from "@/components/shell/app-shell";

export const Route = createFileRoute("/_app")({
  beforeLoad: async () => {
    try {
      const me = await getApi().me();
      useAuth.getState().setAuth({ user: me.user, session: me.session });
    } catch {
      useAuth.getState().setAuth(null);
      throw redirect({ to: "/login", search: { returnTo: window.location.pathname } });
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
