import { create } from "zustand";
import { persist } from "zustand/middleware";

/**
 * 工具标签。
 *
 * 为什么需要：路由切换时 <ToolRunner> 会卸载重挂，
 * 组件里的输入内容、选中项、滚动位置全部丢失。
 * 用户切走再切回来，等于重来一次。
 *
 * 解法与服务器标签一致：把所有打开过的工具**常驻挂载**，
 * 只用 CSS 隐藏非活动的那些。这样组件实例与 DOM 都还在，
 * 状态自然保留。
 *
 * 「初步不允许多开」：同一个工具只保留一个标签，
 * 再次打开时只切换而不新建。
 */

export interface ToolTab {
  /** 工具 id，同时作为标签唯一键 */
  toolId: string;
  /** 显示名（来自工具目录） */
  name: string;
  /** 最近一次激活时间，用于排序 */
  lastActiveAt: number;
}

interface ToolTabsState {
  tabs: ToolTab[];
  activeId: string | null;

  /** 打开（或切换到）某个工具 */
  open: (toolId: string, name: string) => void;
  /** 关闭某个工具标签 */
  close: (toolId: string) => void;
  /** 关闭除自己外的所有标签 */
  closeOthers: (toolId: string) => void;
  /** 直接设置活动标签（导航切换时用） */
  setActive: (toolId: string | null) => void;
}

/** 标签数量上限。打开太多会占用大量内存（每个工具都是常驻 DOM）。 */
const MAX_TABS = 8;

export const useToolTabs = create<ToolTabsState>()(
  persist(
    (set) => ({
      tabs: [],
      activeId: null,

      open: (toolId, name) =>
        set((state) => {
          const existing = state.tabs.find((tab) => tab.toolId === toolId);

          if (existing) {
            // 已打开：只切换并更新活跃时间
            return {
              activeId: toolId,
              tabs: state.tabs.map((tab) =>
                tab.toolId === toolId ? { ...tab, lastActiveAt: Date.now() } : tab,
              ),
            };
          }

          const next: ToolTab = { toolId, name, lastActiveAt: Date.now() };
          // 超出上限时挤掉最久未用的（但不挤掉刚打开的）
          const trimmed =
            state.tabs.length >= MAX_TABS
              ? [...state.tabs]
                  .sort((a, b) => a.lastActiveAt - b.lastActiveAt)
                  .slice(state.tabs.length - MAX_TABS + 1)
              : state.tabs;

          return { tabs: [...trimmed, next], activeId: toolId };
        }),

      close: (toolId) =>
        set((state) => {
          const tabs = state.tabs.filter((tab) => tab.toolId !== toolId);
          // 关掉当前标签时，活动项转到最后一个
          const activeId =
            state.activeId === toolId ? (tabs[tabs.length - 1]?.toolId ?? null) : state.activeId;
          return { tabs, activeId };
        }),

      closeOthers: (toolId) =>
        set((state) => ({
          tabs: state.tabs.filter((tab) => tab.toolId === toolId),
          activeId: toolId,
        })),

      setActive: (toolId) => set({ activeId: toolId }),
    }),
    {
      name: "toolbox.toolTabs",
      // 持久化标签列表，刷新页面后仍在（只存 id 与名称）
      partialize: (state) => ({ tabs: state.tabs, activeId: state.activeId }),
    },
  ),
);
