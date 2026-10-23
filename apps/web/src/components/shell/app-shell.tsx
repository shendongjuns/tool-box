import * as React from "react";
import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";
import { CommandPalette } from "./command-palette";
import { useSettingsQuery } from "@/lib/hooks";
import { useThemeSync } from "@/lib/theme-sync";
import { useApi } from "@/lib/api-context";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { useQueryClient } from "@tanstack/react-query";
import { cn } from "@/lib/utils";

/**
 * 应用壳层：侧栏 + 顶栏 + 内容区。
 *
 * 设置查询在这里统一发起：主题同步与侧栏宽度都依赖同一份 /api/settings，
 * 只请求一次，避免每个子组件各拉一遍。
 */
export function AppShell({ children }: { children: React.ReactNode }) {
  const settings = useSettingsQuery();
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();
  const [commandOpen, setCommandOpen] = React.useState(false);
  // 侧栏折叠状态持久化在服务端设置里（ui.sidebarCollapsed），
  // 刷新/换设备后保持一致。设置未加载完成前默认展开。
  const [collapsed, setCollapsed] = React.useState(false);

  useThemeSync(settings.data?.values);

  /*
   * 侧栏折叠状态：服务端设置优先，本地切换是「未写库前的临时覆盖」。
   *
   * 用 state 记录上次同步过来的值（React 官方「渲染期间调整 state」模式），
   * 不碰 ref、不用 effect —— 两者都会触发 react-hooks 规则告警。
   */
  const savedCollapsed = settings.data?.values["ui.sidebarCollapsed"];
  const [syncedCollapsed, setSyncedCollapsed] = React.useState<boolean | null>(null);
  if (typeof savedCollapsed === "boolean" && syncedCollapsed !== savedCollapsed) {
    setSyncedCollapsed(savedCollapsed);
    setCollapsed(savedCollapsed);
  }

  // 折叠状态写回服务端（失败只静默 —— 本地切换已经生效）
  const persistCollapsed = React.useCallback(
    (next: boolean) => {
      void api
        .putSettings({ values: { "ui.sidebarCollapsed": next } })
        .then(() => queryClient.invalidateQueries({ queryKey: queryKeys.settings(sourceKey) }))
        .catch(() => {
          /* 本地已切换，写库失败不打扰用户 */
        });
    },
    [api, queryClient, sourceKey],
  );

  React.useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setCommandOpen((open) => !open);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      <Sidebar
        collapsed={collapsed}
        onToggle={() => setCollapsed((value) => !value)}
        onTogglePersist={persistCollapsed}
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar onOpenCommand={() => setCommandOpen(true)} />
        <main
          className={cn(
            "min-h-0 flex-1 overflow-y-auto",
            "bg-[radial-gradient(circle_at_100%_0%,color-mix(in_oklch,var(--primary)_7%,transparent),transparent_45%)]",
          )}
        >
          <div className="mx-auto w-full max-w-6xl px-6 py-7">{children}</div>
        </main>
      </div>
      <CommandPalette open={commandOpen} onOpenChange={setCommandOpen} />
    </div>
  );
}