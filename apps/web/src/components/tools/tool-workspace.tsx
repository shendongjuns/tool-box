import { X } from "lucide-react";
import { findTool } from "@toolbox/contracts";
import { useNavigate, useRouterState } from "@tanstack/react-router";
import { cn } from "@/lib/utils";
import { useToolTabs } from "@/features/tools/tool-tabs-store";
import { ToolRunner } from "./tool-runner";

/**
 * 工具工作区：标签栏 + 常驻挂载的工具栏。
 *
 * 关键点是**常驻挂载**：
 * 所有打开过的工具同时存在于 DOM 里，只把非活动的用 hidden 隐藏。
 *
 * 这样 React 不会卸载组件，输入框内容、滚动位置、
 * 甚至图表的历史数据都保留着 —— 这是「切走再切回状态还在」
 * 唯一可靠的实现方式（把状态提到 store 里逐个改造六个工具不现实）。
 *
 * 与服务器标签的设计保持一致：同样的视觉、同样的关闭交互。
 */

/** 自带完整布局的工具（不包默认标题区）。 */
const SELF_LAYOUT = new Set(["servers"]);

export function ToolWorkspace() {
  const { tabs, setActive, close } = useToolTabs();

  /*
   * 活动标签以**路由**为准，而不是 store 里的 activeId。
   *
   * 原因：点侧栏切换工具时，路由先变化、路由组件再在 effect 里
   * 更新 store。如果渲染依赖 store，会出现「标签加了但内容没切」
   * 的一帧延迟，表现为切换失灵。
   * 路由是唯一真相，store 只负责维护「打开了哪些」。
   */
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const navigate = useNavigate();

  const activeId = pathname.startsWith("/tools/")
    ? decodeURIComponent(pathname.slice("/tools/".length))
    : null;

  /** 点标签 = 导航到该工具的路由（路由是唯一真相） */
  const activate = (toolId: string) => {
    setActive(toolId);
    void navigate({ to: "/tools/$toolId", params: { toolId } });
  };

  if (tabs.length === 0) return null;

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      {/* 标签栏 */}
      <div className="flex shrink-0 items-center gap-1.5 overflow-x-auto pb-1">
        {tabs.map((tab) => {
          const tool = findTool(tab.toolId);
          return (
            <div
              key={tab.toolId}
              onClick={() => activate(tab.toolId)}
              role="button"
              aria-label={`切换到工具 ${tab.name}`}
              aria-current={tab.toolId === activeId ? "true" : undefined}
              tabIndex={0}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  activate(tab.toolId);
                }
              }}
              className={cn(
                "group flex min-w-[9rem] max-w-[15rem] shrink-0 cursor-pointer items-center gap-2 rounded-md border px-3 py-2 text-xs transition-colors",
                tab.toolId === activeId
                  ? "border-primary/40 bg-primary/[0.06] font-medium text-foreground"
                  : "border-border text-muted-foreground hover:bg-accent/60",
              )}
              title={tool?.description}
            >
              <span className="min-w-0 flex-1 truncate">{tab.name}</span>
              <button
                type="button"
                onClick={(event) => {
                  event.stopPropagation();
                  const wasActive = tab.toolId === activeId;
                  close(tab.toolId);
                  /*
                   * 关掉的正好是当前标签时，要导航到剩下的最后一个，
                   * 否则路由还停在已关闭的工具上，界面会空白。
                   */
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
                title="关闭"
                aria-label={`关闭 ${tab.name}`}
                className="shrink-0 rounded p-1 text-muted-foreground opacity-0 transition-opacity hover:bg-destructive/10 hover:text-destructive group-hover:opacity-100"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          );
        })}
      </div>

      {/*
        所有工具同时挂载。
        非活动的用 hidden 隐藏 —— 注意不能用条件渲染，
        那会销毁组件、状态全丢。
      */}
      <div className="relative flex min-h-0 flex-1 flex-col">
        {tabs.map((tab) => (
          <div
            key={tab.toolId}
            data-tool-panel={tab.toolId}
            className={cn("min-h-0 flex-1", tab.toolId !== activeId && "hidden")}
          >
            <ToolPanel toolId={tab.toolId} selfLayout={SELF_LAYOUT.has(tab.toolId)} />
          </div>
        ))}
      </div>
    </div>
  );
}

/** 单个工具的容器，负责标题区与内容。 */
function ToolPanel({ toolId, selfLayout }: { toolId: string; selfLayout: boolean }) {
  if (selfLayout) {
    return (
      <div className="flex min-h-0 flex-1 flex-col">
        <ToolRunner toolId={toolId} />
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto">
      <ToolRunner toolId={toolId} />
    </div>
  );
}