import { useNavigate } from "@tanstack/react-router";
import { LogOut, Moon, Search, Settings, Sun, User } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth-session";
import { logoutCurrent } from "@/lib/session";
import { useTheme } from "@/lib/theme";
import { UserAvatar } from "@/components/user-avatar";
import { ToolTabs } from "@/components/tools/tool-tabs";
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
  const navigate = useNavigate();
  const user = useAuth((state) => state.auth?.user);
  const { resolved, setMode, mode } = useTheme();
  async function logout() {
    await logoutCurrent();
    toast.success("已退出登录");
    await navigate({ to: "/login", replace: true });
  }

  return (
    <header className="flex h-14 shrink-0 items-center gap-3 border-b border-border bg-background/80 px-4 backdrop-blur app-drag">
      {/*
        左侧原本是页面标题（"工具"/"设置"…），删除。

        现在这个位置放工具标签栏：它与搜索框同一行，
        用 flex-1 + min-w-0 占据剩余空间，但不设 shrink-0，
        所以永远不会把右侧的搜索/主题/头像挤出去。
        标签数量多时在容器内横向滚动，而不是撑宽整行。
      */}
      <div className="min-w-0 flex-1 overflow-hidden app-no-drag">
        <ToolTabs />
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
            className="app-no-drag rounded-full transition-opacity hover:opacity-80"
            title={user?.username}
          >
            <UserAvatar size={32} />
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