import type { MonitorMetrics, ServerInfo } from "@toolbox/contracts";

/**
 * 监控数据缓存（按会话）。
 *
 * 需求语义：
 * - 切换**会话标签**（顶部）时，监控数据保留，切回来不重新加载
 * - 在同一会话内，从「监控」切到「终端 / 文件」时**彻底关闭**监控
 *   （停止采集并清空缓存，下次进入重新采集）
 *
 * 因此缓存不放在 React state，而是模块级 Map：组件卸载后数据还在，
 * 由调用方显式 `dropMonitor()` 清理。
 */
interface MonitorSnapshot {
  metrics: MonitorMetrics | null;
  info: ServerInfo | null;
  history: MonitorMetrics[];
  error: string | null;
}

const cache = new Map<string, MonitorSnapshot>();

export function readMonitor(sessionId: string): MonitorSnapshot | undefined {
  return cache.get(sessionId);
}

export function writeMonitor(sessionId: string, snapshot: MonitorSnapshot): void {
  cache.set(sessionId, snapshot);
}

/** 彻底关闭某个会话的监控：停采集 + 丢弃数据。 */
export function dropMonitor(sessionId: string): void {
  cache.delete(sessionId);
}
