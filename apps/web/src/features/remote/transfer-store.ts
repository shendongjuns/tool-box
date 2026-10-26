import { create } from "zustand";
import { persist } from "zustand/middleware";

/**
 * 传输任务。
 *
 * 持久化到 localStorage：即使切换页面、刷新或重启应用，
 * 历史任务仍然可见（已完成的记录）。正在传输中的任务在重启后
 * 会被标记为失败，因为 Rust 侧的连接已不存在。
 */
export interface TransferTask {
  id: string;
  name: string;
  direction: "download" | "upload";
  /** 源目录（下载）或目标目录（上传） */
  remoteDir: string;
  /** 下载时的本地保存路径 */
  localPath?: string;
  transferred: number;
  total: number;
  percent: number;
  status: "running" | "done" | "failed";
  error?: string;
  createdAt: number;
}

interface TransferState {
  tasks: TransferTask[];
  add: (task: TransferTask) => void;
  patch: (id: string, next: Partial<TransferTask>) => void;
  remove: (id: string) => void;
  clearFinished: () => void;
  /** 应用重启后把「进行中」标记为中断 */
  markInterrupted: () => void;
}

export const useTransfers = create<TransferState>()(
  persist(
    (set) => ({
      tasks: [],

      add: (task) => set((state) => ({ tasks: [task, ...state.tasks].slice(0, 50) })),

      patch: (id, next) =>
        set((state) => ({
          tasks: state.tasks.map((task) => (task.id === id ? { ...task, ...next } : task)),
        })),

      remove: (id) => set((state) => ({ tasks: state.tasks.filter((task) => task.id !== id) })),

      clearFinished: () =>
        set((state) => ({ tasks: state.tasks.filter((task) => task.status === "running") })),

      markInterrupted: () =>
        set((state) => ({
          tasks: state.tasks.map((task) =>
            task.status === "running"
              ? { ...task, status: "failed", error: "应用已重启，传输中断" }
              : task,
          ),
        })),
    }),
    {
      name: "toolbox.transfers",
      // 只持久化任务元数据；running 状态在恢复时会被改写
      partialize: (state) => ({ tasks: state.tasks }),
    },
  ),
);
// 应用启动时把上次残留的「进行中」标记为中断，
// 否则重启后会看到永远卡在某个百分比的幽灵任务。
if (typeof window !== "undefined") {
  useTransfers.getState().markInterrupted();
}
