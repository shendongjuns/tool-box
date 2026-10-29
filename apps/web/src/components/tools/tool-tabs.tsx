import { useNavigate, useRouterState } from "@tanstack/react-router";
import { X } from "lucide-react";
import { findTool } from "@toolbox/contracts";
import { cn } from "@/lib/utils";
import { useToolTabs } from "@/features/tools/tool-tabs-store";

/**
 * 工具标签栏（顶栏内联版）。
 *
 * 放在搜索框左边同一行。设计要求：
 * - **不能挤压其它区域**：容器用 min-w-0 + overflow-hidden，
 *   标签本身 shrink-0 且限宽，超出部分横向滚动
 * - 高度与搜索框对齐（h-8），视觉上属于同一行控件
 * - 只在 /tools/* 下出现；其它页面该位置留空
 *
 * 活动标签以路由为准（不是 store），原因见 tool-workspace.tsx。
 */
export function ToolTabs() {
  const { tabs, close } = useToolTabs();
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const navigate = useNavigate();

  const inTools = pathname.startsWith("/tools/");
  const activeId = inTools ? decodeURIComponent(pathname.slice("/tools/".length)) : null;

  // 不在工具区、或没有标签时不占位
  if (!inTools || tabs.length === 0) return null;

  const activate = (toolId: string) => {
    void navigate({ to: "/tools/$toolId", params: { toolId } });
  };

  return (
    <div
      role="tablist"
      aria-label="已打开的工具"
      /*
       * overflow-x-auto：标签多时在本区域内滚动。
       * 外层还有 overflow-hidden 兜底，保证即使滚动条出现
       * 也不会把右侧控件挤走。
       */
      className="flex h-8 items-center gap-1 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
    >
      {tabs.map((tab) => {
        const tool = findTool(tab.toolId);
        const isActive = tab.toolId === activeId;

        return (
          <div
            key={tab.toolId}
            role="tab"
            aria-selected={isActive}
            aria-label={`${tab.name}${isActive ? "（当前）" : ""}`}
            tabIndex={0}
            onClick={() => activate(tab.toolId)}
            onKeyDown={(event) => {
              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                activate(tab.toolId);
              }
            }}
            title={tool?.description}
            className={cn(
              // shrink-0 + max-w：单个标签不会被压扁，也不会无限变宽
              "group flex h-8 shrink-0 cursor-pointer items-center gap-1.5 rounded-md border px-2.5 text-xs transition-colors",
              isActive
                ? "border-primary/40 bg-primary/[0.06] font-medium text-foreground"
                : "border-transparent text-muted-foreground hover:border-border hover:bg-accent/60",
            )}
          >
            <span className="max-w-[7rem] truncate">{tab.name}</span>
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                const wasActive = isActive;
                close(tab.toolId);
                // 关掉当前标签时要导航走，否则路由停在已关闭的工具上
                if (wasActive) {
                  const remaining = tabs.filter((item) => item.toolId !== tab.toolId);
                  const next = remaining[remaining.length - 1];
                  if (next) {
                    void navigate({ to: "/tools/$toolId", params: { toolId: next.toolId } });
                  } else {
                    void navigate({ to: "/dashboard" });
                  }
                }
              }}
              title={`关闭 ${tab.name}`}
              aria-label={`关闭 ${tab.name}`}
              className={cn(
                "-mr-0.5 shrink-0 rounded p-0.5 transition-opacity hover:bg-destructive/10 hover:text-destructive",
                isActive ? "opacity-60 hover:opacity-100" : "opacity-0 group-hover:opacity-100",
              )}
            >
              <X className="h-3 w-3" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
