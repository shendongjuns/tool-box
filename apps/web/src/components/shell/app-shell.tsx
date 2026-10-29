import * as React from "react";
import { useRouterState } from "@tanstack/react-router";
import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";
import { ToolWorkspace } from "@/components/tools/tool-workspace";
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
            "flex min-h-0 flex-1 flex-col overflow-y-auto",
            "bg-[radial-gradient(circle_at_100%_0%,color-mix(in_oklch,var(--primary)_7%,transparent),transparent_45%)]",
          )}
        >
          {/*
            高度用 100% 而不是 100vh 计算：
            窗口最大化 / 全屏后，顶栏与内边距都不变，
            但 vh 会把浏览器 chrome 算进去，导致内容溢出或留白。
          */}
          <div className="mx-auto flex w-full max-w-6xl flex-1 flex-col px-6 py-7">
            {/*
              工具工作区常驻在这里，而不是在工具路由里。

              原因：工具路由切换会卸载组件，输入内容与滚动位置全丢。
              放在 AppShell 层后，只要还在 /tools/* 下，
              ToolWorkspace 就一直挂着，只有离开整个工具区才卸载。

              {children} 在工具页时渲染 null（路由组件只登记标签），
              所以不会重复渲染。
            */}
            <ToolArea />
            {children}
          </div>
        </main>
      </div>
      <CommandPalette open={commandOpen} onOpenChange={setCommandOpen} />
    </div>
  );
}
/**
 * 工具区。
 *
 * 仅在 /tools/* 路由下显示工作区；其余页面显示 children。
 * 用一个判断避免「仪表盘和工具同时出现」。
 */
function ToolArea() {
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const inTools = pathname.startsWith("/tools/");
  if (!inTools) return null;
  return <ToolWorkspace />;
}
