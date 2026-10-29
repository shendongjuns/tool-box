import { isTauriRuntime } from "./platform";

/**
 * 云端延迟探测。
 *
 * 对某个服务器地址发起一次轻量请求，测量往返时间（RTT）。
 *
 * - 成功：返回毫秒数
 * - 超时 / 不可达：返回 "timeout" 或 "offline"，**不是 null**
 *   —— 界面需要显示「超时」「不可达」，而不是空白
 *
 * 探测本身也有超时（默认 3 秒），保证一定能出结果。
 */
export type LatencyResult =
  | { kind: "ok"; ms: number }
  | { kind: "timeout"; ms: number }
  | { kind: "offline"; ms: number; reason: string };

const PROBE_TIMEOUT_MS = 3000;

/**
 * 探测地址延迟。
 *
 * 桌面端经 Rust 转发（与真实业务请求同一条链路，测出来的值才有意义）；
 * 网页端直接 fetch。
 */
export async function probeLatency(url: string): Promise<LatencyResult> {
  const base = url.replace(/\/$/, "");
  const target = `${base}/api/health`;
  const started = performance.now();

  const elapsed = () => Math.round(performance.now() - started);

  // 桌面端：走 Rust 转发（CSP 不允许渲染层直连外部地址）
  if (isTauriRuntime()) {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const timeout = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error("timeout")), PROBE_TIMEOUT_MS);
      });
      const result = (await Promise.race([
        invoke("http_request", {
          method: "GET",
          url: target,
          headers: { accept: "application/json" },
        }),
        timeout,
      ])) as { status: number; body: string };

      const ms = elapsed();
      // 能拿到 HTTP 响应就算通（哪怕 4xx：说明网络是通的）
      if (result.status > 0) return { kind: "ok", ms };
      return { kind: "offline", ms, reason: "无响应" };
    } catch (error) {
      const ms = elapsed();
      const message = error instanceof Error ? error.message : String(error);
      if (message.includes("timeout") || ms >= PROBE_TIMEOUT_MS - 100) {
        return { kind: "timeout", ms };
      }
      return { kind: "offline", ms, reason: message.slice(0, 60) };
    }
  }

  // 网页端：直接 fetch（同源或目标已开 CORS）
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS);
  try {
    await fetch(target, {
      method: "GET",
      signal: controller.signal,
      cache: "no-store",
    });
    return { kind: "ok", ms: elapsed() };
  } catch (error) {
    const ms = elapsed();
    if (controller.signal.aborted) return { kind: "timeout", ms };
    return {
      kind: "offline",
      ms,
      reason: error instanceof Error ? error.message.slice(0, 60) : "网络不可达",
    };
  } finally {
    clearTimeout(timer);
  }
}

/** 延迟的展示文案与颜色。 */
export function describeLatency(result: LatencyResult | null): {
  text: string;
  tone: "good" | "fair" | "poor" | "dead" | "unknown";
} {
  if (!result) return { text: "检测中…", tone: "unknown" };

  if (result.kind === "timeout")
    return { text: `超时（>${PROBE_TIMEOUT_MS / 1000}s）`, tone: "dead" };
  if (result.kind === "offline") return { text: "不可达", tone: "dead" };

  const ms = result.ms;
  if (ms < 80) return { text: `${ms} ms`, tone: "good" };
  if (ms < 200) return { text: `${ms} ms`, tone: "fair" };
  return { text: `${ms} ms`, tone: "poor" };
}
