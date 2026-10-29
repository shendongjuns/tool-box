import type { MonitorMetrics, ServerInfo } from "@toolbox/contracts";

/**
 * 监控数据缓存与采集引擎（按会话）。
 *
 * 设计要点：**采集不依赖界面**。
 * 定时器跑在模块级（不在 React 组件里），因此：
 * - 切到「终端 / 文件」时，采集继续在后台记录
 * - 切换到别的会话标签，本会话的采集也不中断
 * - 只有 dropMonitor()（关闭监控或关闭会话）才真正停止
 *
 * 组件只负责「读快照 + 订阅变更」，不持有定时器。
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
  // 注意：getItem 返回 null 时 Number(null) === 0，
  // 会被误判成「暂停」—— 必须先判空。
  if (raw === null || raw === "") return DEFAULT_INTERVAL;

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

// ---------------- 采集引擎 ----------------

/**
 * 每个会话一个采集引擎。
 *
 * 关键设计：**用 setTimeout 自递归而不是 setInterval**。
 * setInterval 在前一次采集未完成时仍会触发下一次，机器卡顿时会堆积；
 * 自递归保证「上次完成后再排下一次」，永远不会重叠。
 *
 * 引擎存活于模块级，与 React 组件生命周期无关 ——
 * 这就是「切到其他标签后仍在后台记录」的实现基础。
 */
interface Engine {
  timer: number | null;
  /** 已停止（dropMonitor 后为 true） */
  stopped: boolean;
  interval: RefreshInterval;
  /** 采集函数，由调用方注入 */
  collect: () => Promise<void>;
}

const engines = new Map<string, Engine>();

type Listener = (sessionId: string) => void;
const listeners = new Set<Listener>();

export function subscribeMonitor(listener: Listener): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function notifyMonitor(sessionId: string): void {
  for (const listener of listeners) listener(sessionId);
}

/** 排下一次采集。 */
function schedule(sessionId: string): void {
  const engine = engines.get(sessionId);
  if (!engine || engine.stopped) return;

  // 清掉旧定时器，避免重复排程
  if (engine.timer !== null) {
    window.clearTimeout(engine.timer);
    engine.timer = null;
  }

  if (engine.interval === 0) return; // 暂停

  engine.timer = window.setTimeout(() => {
    const current = engines.get(sessionId);
    if (!current || current.stopped) return;

    current.timer = null;
    void (async () => {
      try {
        await current.collect();
      } catch {
        /* 采集异常不中断循环 */
      }
      // 采集结束后再排下一次
      schedule(sessionId);
    })();
  }, engine.interval);
}

/**
 * 启动或更新某个会话的采集。
 *
 * 幂等：重复调用只更新间隔与采集函数，不会产生第二个定时器。
 */
export function startMonitor(
  sessionId: string,
  interval: RefreshInterval,
  collect: () => Promise<void>,
): void {
  const existing = engines.get(sessionId);

  if (existing) {
    existing.interval = interval;
    existing.collect = collect;
    existing.stopped = false;
    schedule(sessionId);
    return;
  }

  engines.set(sessionId, { timer: null, stopped: false, interval, collect });
  schedule(sessionId);
}

/** 彻底关闭：停采集 + 丢数据 + 通知界面。 */
export function dropMonitor(sessionId: string): void {
  const engine = engines.get(sessionId);
  if (engine) {
    engine.stopped = true;
    if (engine.timer !== null) window.clearTimeout(engine.timer);
    engines.delete(sessionId);
  }
  cache.delete(sessionId);
  notifyMonitor(sessionId);
}

/** 引擎是否在跑。 */
export function isMonitoring(sessionId: string): boolean {
  const engine = engines.get(sessionId);
  return Boolean(engine && !engine.stopped && engine.interval > 0);
}
