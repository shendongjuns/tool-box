import { create } from "zustand";
import type { Server } from "@toolbox/contracts";

/**
 * 多会话管理。
 *
 * 每个打开的服务器是独立会话，各自有：
 * - 唯一的 sessionId（对应 Rust 侧连接）
 * - 自己的终端输出缓冲（由 TerminalHost 持有）
 * - 自己的当前标签页
 *
 * 关键：**会话的终端组件必须常驻挂载**。
 * 之前用 Tabs 的 TabsContent，切到「文件」时终端被卸载，
 * React 销毁了 xterm 实例和它的回滚缓冲 —— 切回来内容就空了。
 * 现在改为所有会话的终端都挂在 DOM 里，只用 CSS 隐藏非活动项。
 */
export interface RemoteSession {
  id: string;
  server: Server;
  /** Rust 侧连接 id */
  sshSessionId: string;
  /** 标签显示名，同一服务器多开时自动加序号 */
  label: string;
  tab: "terminal" | "files" | "monitor";
  connected: boolean;
}

/**
 * 生成不重名的标签名。
 *
 * 规则：第一次打开用服务器名；重复打开依次变成
 * `名称（1）`、`名称（2）`…，直到找到未占用的名字。
 */
export function nextLabel(base: string, existing: readonly string[]): string {
  const name = base.trim() || "未命名";
  if (!existing.includes(name)) return name;

  let index = 1;
  while (existing.includes(`${name}（${index}）`)) index += 1;
  return `${name}（${index}）`;
}

interface SessionState {
  sessions: RemoteSession[];
  activeId: string | null;

  add: (session: RemoteSession) => void;
  remove: (id: string) => void;
  setActive: (id: string) => void;
  setTab: (id: string, tab: RemoteSession["tab"]) => void;
  markDisconnected: (sshSessionId: string) => void;
  clear: () => void;
}

export const useRemoteSessions = create<SessionState>((set) => ({
  sessions: [],
  activeId: null,

  add: (session) =>
    set((state) => ({
      sessions: [...state.sessions, session],
      activeId: session.id,
    })),

  remove: (id) =>
    set((state) => {
      const sessions = state.sessions.filter((item) => item.id !== id);
      const activeId =
        state.activeId === id ? (sessions[sessions.length - 1]?.id ?? null) : state.activeId;
      return { sessions, activeId };
    }),

  setActive: (id) => set({ activeId: id }),

  setTab: (id, tab) =>
    set((state) => ({
      sessions: state.sessions.map((item) => (item.id === id ? { ...item, tab } : item)),
    })),

  markDisconnected: (sshSessionId) =>
    set((state) => ({
      sessions: state.sessions.map((item) =>
        item.sshSessionId === sshSessionId ? { ...item, connected: false } : item,
      ),
    })),

  clear: () => set({ sessions: [], activeId: null }),
}));