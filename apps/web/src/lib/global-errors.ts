import { toast } from "sonner";

/**
 * 全局未捕获异常处理。
 *
 * 之前没有任何兜底：
 * - 未捕获的 Promise rejection 完全静默，用户只看到「点了没反应」
 * - 渲染期外的同步异常直接进控制台，用户看不见
 *
 * 这里统一接管并给出可见反馈。同一个错误在 5 秒内只提示一次，
 * 避免循环报错刷屏。
 */

const RECENT_WINDOW_MS = 5000;
const recent = new Map<string, number>();

function reportOnce(message: string): void {
  const now = Date.now();
  const last = recent.get(message);
  if (last && now - last < RECENT_WINDOW_MS) return;
  recent.set(message, now);

  // 防止 map 无限增长
  if (recent.size > 50) {
    for (const [key, time] of recent) {
      if (now - time > RECENT_WINDOW_MS) recent.delete(key);
    }
  }

  toast.error("操作未完成", {
    description: message.slice(0, 120),
    duration: 6000,
  });
}

/** 安装全局监听。返回卸载函数。 */
export function installGlobalErrorHandlers(): () => void {
  const onError = (event: ErrorEvent) => {
    const message = event.message || "未知错误";
    console.error("未捕获异常", event.error ?? message);
    reportOnce(message);
  };

  const onRejection = (event: PromiseRejectionEvent) => {
    const reason = event.reason;
    const message =
      reason instanceof Error ? reason.message : typeof reason === "string" ? reason : "未知异常";
    console.error("未处理的 Promise 拒绝", reason);
    reportOnce(message);
  };

  window.addEventListener("error", onError);
  window.addEventListener("unhandledrejection", onRejection);

  return () => {
    window.removeEventListener("error", onError);
    window.removeEventListener("unhandledrejection", onRejection);
  };
}
