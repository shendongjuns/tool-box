import * as React from "react";
import { cn } from "@/lib/utils";
import { describeLatency, probeLatency, type LatencyResult } from "@/lib/latency";

/**
 * 云端延迟徽标。
 *
 * 挂载时探测一次，点击可重新探测。
 * 网络不通时也必须有展示 —— 显示「超时」或「不可达」，不能空白。
 */
export function LatencyBadge({
  url,
  className,
  autoProbe = true,
}: {
  url: string;
  className?: string;
  autoProbe?: boolean;
}) {
  const [result, setResult] = React.useState<LatencyResult | null>(null);
  const [probing, setProbing] = React.useState(false);

  const run = React.useCallback(async () => {
    if (!url) return;
    setProbing(true);
    try {
      setResult(await probeLatency(url));
    } finally {
      setProbing(false);
    }
  }, [url]);

  React.useEffect(() => {
    if (!autoProbe) return;
    let cancelled = false;
    void (async () => {
      setProbing(true);
      try {
        const next = await probeLatency(url);
        if (!cancelled) setResult(next);
      } finally {
        if (!cancelled) setProbing(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [url, autoProbe]);

  const { text, tone } = probing && !result ? { text: "检测中…", tone: "unknown" as const } : describeLatency(result);

  const toneClass = {
    good: "text-emerald-600 dark:text-emerald-400 border-emerald-500/30 bg-emerald-500/10",
    fair: "text-amber-600 dark:text-amber-400 border-amber-500/30 bg-amber-500/10",
    poor: "text-orange-600 dark:text-orange-400 border-orange-500/30 bg-orange-500/10",
    dead: "text-red-600 dark:text-red-400 border-red-500/30 bg-red-500/10",
    unknown: "text-muted-foreground border-border bg-muted/50",
  }[tone];

  return (
    <button
      type="button"
      onClick={() => void run()}
      disabled={probing}
      title={probing ? "正在检测延迟" : "点击重新检测"}
      className={cn(
        "inline-flex shrink-0 items-center gap-1 rounded-full border px-1.5 py-0.5 text-[10px] font-medium tabular-nums transition-opacity",
        toneClass,
        probing && "opacity-60",
        className,
      )}
    >
      <span
        className={cn(
          "h-1.5 w-1.5 rounded-full",
          tone === "good" && "bg-emerald-500",
          tone === "fair" && "bg-amber-500",
          tone === "poor" && "bg-orange-500",
          tone === "dead" && "bg-red-500",
          tone === "unknown" && "bg-muted-foreground/50",
        )}
      />
      {text}
    </button>
  );
}
