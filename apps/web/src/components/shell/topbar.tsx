import { useNavigate, useRouterState } from "@tanstack/react-router";
import { LogOut, Moon, Search, Settings, Sun, User } from "lucide-react";
import { toast } from "sonner";
import { useApi } from "@/lib/api-context";
import { useAuth } from "@/lib/auth-session";
import { clearSession } from "@/lib/session";
import { useTheme } from "@/lib/theme";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export function Topbar({ onOpenCommand }: { onOpenCommand: () => void }) {
  const api = useApi();
  const navigate = useNavigate();
  const user = useAuth((state) => state.auth?.user);
  const { resolved, setMode, mode } = useTheme();
  const pathname = useRouterState({ select: (state) => state.location.pathname });

  const title =
    pathname === "/dashboard"
      ? "仪表盘"
      : pathname === "/settings"
        ? "设置"
        : pathname.startsWith("/tools/")
          ? "工具"
          : "ToolBox";

  async function logout() {
    try {
      await api.logout();
    } catch {
      // 服务端不可达时也要让本地退出，不能把用户困在已登录界面
    }
    await clearSession();
    toast.success("已退出登录");
    await navigate({ to: "/login" });
  }

  return (
    <header className="flex h-14 shrink-0 items-center gap-3 border-b border-border bg-background/80 px-4 backdrop-blur app-drag">
      <div className="min-w-0 flex-1 app-no-drag">
        <p className="truncate text-sm font-medium">{title}</p>
      </div>

      <button
        type="button"
        onClick={onOpenCommand}
        className="app-no-drag inline-flex h-8 items-center gap-2 rounded-md border border-border bg-card px-2.5 text-xs text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
      >
        <Search className="h-3.5 w-3.5" />
        <span className="hidden sm:inline">搜索工具</span>
        <kbd className="ml-2 hidden rounded border border-border bg-muted px-1 font-mono text-[10px] sm:inline">
          Ctrl K
        </kbd>
      </button>

      <Button
        variant="ghost"
        size="icon-sm"
        className="app-no-drag"
        onClick={() => setMode(mode === "dark" ? "light" : "dark")}
        title={resolved === "dark" ? "切换到浅色" : "切换到深色"}
      >
        {resolved === "dark" ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
      </Button>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            className="app-no-drag grid h-8 w-8 place-items-center rounded-full bg-primary/12 text-xs font-semibold text-primary transition-colors hover:bg-primary/20"
            title={user?.username}
          >
            {(user?.displayName ?? user?.username ?? "U").slice(0, 1).toUpperCase()}
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-52">
          <DropdownMenuLabel>{user?.displayName ?? user?.username}</DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onSelect={() => void navigate({ to: "/settings", search: { tab: "account" } })}
          >
            <User className="h-4 w-4" />
            账户与安全
          </DropdownMenuItem>
          <DropdownMenuItem
            onSelect={() => void navigate({ to: "/settings", search: { tab: "general" } })}
          >
            <Settings className="h-4 w-4" />
            设置
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem destructive onSelect={() => void logout()}>
            <LogOut className="h-4 w-4" />
            退出登录
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </header>
  );
}
