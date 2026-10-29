import { useRouterState } from "@tanstack/react-router";
import { cn } from "@/lib/utils";
import { useToolTabs } from "@/features/tools/tool-tabs-store";
import { ToolRunner } from "./tool-runner";

/**
 * 工具工作区：常驻挂载的工具面板。
 *
 * 标签栏在顶栏（见 components/tools/tool-tabs.tsx），
 * 这里只负责把打开过的工具全部挂载、按需显示。
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
  const { tabs } = useToolTabs();

  /*
   * 活动标签以**路由**为准，而不是 store 里的 activeId。
   *
   * 原因：点侧栏切换工具时，路由先变化、路由组件再在 effect 里
   * 更新 store。如果渲染依赖 store，会出现「标签加了但内容没切」
   * 的一帧延迟。
   */
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const activeId = pathname.startsWith("/tools/")
    ? decodeURIComponent(pathname.slice("/tools/".length))
    : null;

  if (tabs.length === 0) return null;

  return (
    /*
     * 所有工具同时挂载，非活动的用 hidden 隐藏。
     *
     * 这是「切走再切回状态还在」的唯一可靠实现 ——
     * 条件渲染会销毁组件，输入内容与滚动位置全部丢失。
     *
     * 标签栏不在这里（已移到顶栏），所以这个容器只负责摆放面板。
     */
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
