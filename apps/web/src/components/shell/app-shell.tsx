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
          /*
           * 这里**不能**加 overflow-y-auto。
           *
           * 加了之后，内容一旦超过窗口高度，滚动条就长在 main 上，
           * 内部的 flex-1 链失去高度约束 —— 表现是文件列表、
           * 终端这些本该独立滚动的区域不再独立，整个页面一起滚。
           *
           * 正确做法：main 只负责布局（撑满剩余高度、不分段），
           * 具体哪个区域要滚动由内层组件自己决定。
           */
          className={cn(
            "flex min-h-0 flex-1 flex-col overflow-hidden",
            "bg-[radial-gradient(circle_at_100%_0%,color-mix(in_oklch,var(--primary)_7%,transparent),transparent_45%)]",
          )}
        >
          {/*
            高度用 100% 而不是 100vh 计算：
            窗口最大化 / 全屏后，顶栏与内边距都不变，
            但 vh 会把浏览器 chrome 算进去，导致内容溢出或留白。
          */}
          {/*
            内层容器负责滚动。
            
            区分两种页面：
            - 普通页面（仪表盘/设置）：内容超出时在这里滚动
            - 工具区（/tools/*）：由 ToolWorkspace 内部的各个面板
              自己决定谁滚（文件列表、终端输出各滚各的），
              这里不能滚，否则整页一起动。
          */}
          <ContentArea>{children}</ContentArea>
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
/**
 * 内容区。
 *
 * 工具页与非工具页的滚动行为不同：
 * - 工具页：容器不可滚，让内部面板自己滚（文件列表、终端输出）
 * - 普通页：容器可滚，内容超出窗口时在这里滚动
 *
 * 之前 main 上加了 overflow-y-auto，导致两种页面共用同一个
 * 滚动容器 —— 文件列表一长，整页跟着滚，切标签要滚很久。
 */
function ContentArea({ children }: { children: React.ReactNode }) {
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const inTools = pathname.startsWith("/tools/");

  return (
    <div
      className={cn(
        "mx-auto flex min-h-0 w-full max-w-6xl flex-1 flex-col px-6 py-7",
        // 普通页自己滚；工具页交给内部面板
        !inTools && "overflow-y-auto",
      )}
    >
      <ToolArea />
      {children}
    </div>
  );
}

function ToolArea() {
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const inTools = pathname.startsWith("/tools/");
  if (!inTools) return null;
  return <ToolWorkspace />;
}
