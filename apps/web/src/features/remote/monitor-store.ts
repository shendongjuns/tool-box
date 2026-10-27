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
/** 刷新间隔（毫秒）；0 表示暂停。 */
export type RefreshInterval = 0 | 1000 | 3000 | 10000;

export const REFRESH_OPTIONS: { value: RefreshInterval; label: string }[] = [
  { value: 0, label: "暂停" },
  { value: 1000, label: "1s" },
  { value: 3000, label: "3s" },
  { value: 10000, label: "10s" },
];

const STORAGE_KEY = "toolbox.monitor.interval";
const DEFAULT_INTERVAL: RefreshInterval = 1000;

/** 读取上次选择的刷新间隔。默认 1s。 */
export function readRefreshInterval(): RefreshInterval {
  if (typeof window === "undefined") return DEFAULT_INTERVAL;
  const raw = window.localStorage.getItem(STORAGE_KEY);
  const parsed = Number(raw);
  return parsed === 0 || parsed === 1000 || parsed === 3000 || parsed === 10000
    ? (parsed as RefreshInterval)
    : DEFAULT_INTERVAL;
}

export function saveRefreshInterval(value: RefreshInterval): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(STORAGE_KEY, String(value));
}

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