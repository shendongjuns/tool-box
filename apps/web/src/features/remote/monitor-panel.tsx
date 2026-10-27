import * as React from "react";
import {
  Cpu,
  HardDrive,
  MemoryStick,
  Network,
  Search,
  Server,
  Thermometer,
  X,
} from "lucide-react";
import type { MonitorMetrics, ServerInfo } from "@toolbox/contracts";
import { cn } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { CpuChart, DiskBars, GpuCharts, MemoryChart, NetworkChart, NpuCharts } from "./charts";
import { formatBytes } from "./format";

/** 使用率对应的文字色。 */
function toneClass(percent: number): string {
  if (percent >= 90) return "text-red-600 dark:text-red-400";
  if (percent >= 75) return "text-orange-600 dark:text-orange-400";
  if (percent >= 50) return "text-amber-600 dark:text-amber-400";
  return "text-emerald-600 dark:text-emerald-400";
}

/** 顶部指标卡：数值 + 迷你趋势。 */
function MetricCard({
  label,
  icon: Icon,
  value,
  sub,
  children,
}: {
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  value: string;
  sub?: string;
  children?: React.ReactNode;
}) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="mb-1 flex items-center justify-between">
          <span className="flex items-center gap-1.5 text-[11px] font-medium text-muted-foreground">
            <Icon className="h-3.5 w-3.5" />
            {label}
          </span>
          <span className="text-lg font-semibold tabular-nums leading-none">{value}</span>
        </div>
        {sub ? <p className="mb-1 text-[10px] text-muted-foreground">{sub}</p> : null}
        {children}
      </CardContent>
    </Card>
  );
}

/** 监控面板。 */
export function MonitorPanel({
  metrics,
  info,
  loading,
  error,
  history = [],
}: {
  metrics: MonitorMetrics | null;
  info: ServerInfo | null;
  loading: boolean;
  error: string | null;
  history?: MonitorMetrics[];
}) {
  if (error) {
    return (
      <div className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">
        {error}
      </div>
    );
  }

  if (loading && !metrics) {
    return (
      <div className="grid gap-3 sm:grid-cols-2">
        {[0, 1, 2, 3].map((index) => (
          <Skeleton key={index} className="h-32 w-full" />
        ))}
      </div>
    );
  }

  if (!metrics) {
    return <p className="py-8 text-center text-sm text-muted-foreground">正在采集第一组数据…</p>;
  }

  const memPercent = metrics.memTotalBytes
    ? (metrics.memUsedBytes / metrics.memTotalBytes) * 100
    : 0;

  return (
    <div className="space-y-3">
      {/* 服务器信息 */}
      {info ? (
        <Card>
          <CardContent className="flex flex-wrap items-center gap-x-5 gap-y-1 p-2.5 text-[11px]">
            <span className="flex items-center gap-1.5 font-medium">
              <Server className="h-3.5 w-3.5 text-primary" />
              {info.hostname || "未知主机"}
            </span>
            {info.ip ? <span className="text-muted-foreground">{info.ip}</span> : null}
            {info.os ? <span className="text-muted-foreground">{info.os}</span> : null}
            {info.kernel ? <span className="text-muted-foreground">kernel {info.kernel}</span> : null}
            {info.cpuModel ? (
              <span className="max-w-[20rem] truncate text-muted-foreground">
                {info.cpuModel} · {info.cpuCores} 核
              </span>
            ) : null}
            {metrics.swapTotalBytes > 0 ? (
              <span className="rounded-full border border-border px-2 py-0.5 text-[10px] text-muted-foreground">
                Swap {formatBytes(metrics.swapUsedBytes)} / {formatBytes(metrics.swapTotalBytes)}
              </span>
            ) : (
              <span className="rounded-full border border-border/50 px-2 py-0.5 text-[10px] text-muted-foreground/60">
                Swap 未启用
              </span>
            )}
          </CardContent>
        </Card>
      ) : null}

      {/* 核心指标 + 趋势图 */}
      <div className="grid gap-3 lg:grid-cols-2">
        <MetricCard
          label="CPU"
          icon={Cpu}
          value={`${metrics.cpuPercent.toFixed(1)}%`}
          sub={`${metrics.cpuCores} 核 · 负载 ${metrics.load1.toFixed(2)}`}
        >
          <CpuChart data={history} />
        </MetricCard>

        <MetricCard
          label="内存"
          icon={MemoryStick}
          value={`${memPercent.toFixed(0)}%`}
          sub={`${formatBytes(metrics.memUsedBytes)} / ${formatBytes(metrics.memTotalBytes)}`}
        >
          <MemoryChart data={history} />
        </MetricCard>
      </div>

      <MetricCard
        label="网络"
        icon={Network}
        value={`${(metrics.netRxBytesPerSec / 1048576).toFixed(2)} MiB/s`}
        sub={`上行 ${(metrics.netTxBytesPerSec / 1048576).toFixed(2)} MiB/s`}
      >
        <NetworkChart data={history} />
      </MetricCard>

      {/* GPU：趋势图 + 每卡详情 */}
      {metrics.gpus.length > 0 ? (
        <Card>
          <CardHeader className="p-3 pb-1">
            <CardTitle className="flex items-center gap-1.5 text-[11px] font-medium text-muted-foreground">
              <Thermometer className="h-3.5 w-3.5" />
              GPU
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 p-3 pt-1">
            <GpuCharts data={history} />
            <div className="space-y-0.5 border-t border-border/40 pt-1.5 text-[10px] text-muted-foreground">
              {metrics.gpus.map((gpu) => (
                <div key={gpu.index} className="flex items-center justify-between gap-2">
                  <span className="truncate">
                    #{gpu.index} {gpu.name}
                  </span>
                  <span className="shrink-0 font-mono tabular-nums">
                    {gpu.memUsedMiB}/{gpu.memTotalMiB} MiB
                  </span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      ) : null}

      {/* NPU：与 GPU 同样的四联图 + 设备明细 */}
      {metrics.npus.length > 0 ? (
        <Card>
          <CardHeader className="p-3 pb-1">
            <CardTitle className="text-[11px] font-medium text-muted-foreground">
              NPU（昇腾）
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 p-3 pt-1">
            <NpuCharts data={history} />
            <div className="space-y-1 border-t border-border/40 pt-1.5 text-[10px]">
              {metrics.npus.map((npu) => (
                <div key={npu.index} className="flex items-center justify-between gap-2">
                  <span className="flex min-w-0 items-center gap-1.5">
                    <span className="shrink-0 font-mono text-muted-foreground">
                      #{npu.index}
                    </span>
                    <span className="truncate text-muted-foreground">{npu.name}</span>
                  </span>
                  <span
                    className={cn(
                      "shrink-0 rounded px-1.5 py-0.5 font-medium",
                      /ok/i.test(npu.health)
                        ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400"
                        : "bg-amber-500/15 text-amber-600 dark:text-amber-400",
                    )}
                  >
                    {npu.health}
                  </span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      ) : null}

      {/* 进程（带关键字过滤） */}
      {metrics.processes.length > 0 ? (
        <ProcessTable processes={metrics.processes} />
      ) : null}

      {/* 磁盘：放最下 */}
      {metrics.disks.length > 0 ? (
        <Card>
          <CardHeader className="p-3 pb-1">
            <CardTitle className="flex items-center gap-1.5 text-[11px] font-medium text-muted-foreground">
              <HardDrive className="h-3.5 w-3.5" />
              磁盘
            </CardTitle>
          </CardHeader>
          <CardContent className="p-3 pt-2">
            <DiskBars disks={metrics.disks} />
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}

/** TOP 进程表：支持按命令关键字过滤。 */
function ProcessTable({ processes }: { processes: MonitorMetrics["processes"] }) {
  const [keyword, setKeyword] = React.useState("");

  const filtered = React.useMemo(() => {
    const query = keyword.trim().toLowerCase();
    if (!query) return processes;
    return processes.filter((proc) => proc.name.toLowerCase().includes(query));
  }, [processes, keyword]);

  return (
    <Card>
      <CardHeader className="p-3 pb-1">
        <div className="flex items-center justify-between gap-2">
          <CardTitle className="text-[11px] font-medium text-muted-foreground">
            CPU 占用 TOP
            {keyword ? ` · ${filtered.length} 条匹配` : ""}
          </CardTitle>
          <div className="relative">
            <Search className="pointer-events-none absolute left-2 top-1/2 h-3 w-3 -translate-y-1/2 text-muted-foreground/60" />
            <input
              value={keyword}
              onChange={(event) => setKeyword(event.target.value)}
              placeholder="筛选命令…"
              className="h-6 w-40 rounded-md border border-input bg-[var(--card)] pl-7 pr-2 text-[11px] outline-none focus-visible:border-[var(--ring)]"
            />
            {keyword ? (
              <button
                type="button"
                onClick={() => setKeyword("")}
                className="absolute right-1.5 top-1/2 -translate-y-1/2 rounded p-0.5 text-muted-foreground hover:text-foreground"
              >
                <X className="h-3 w-3" />
              </button>
            ) : null}
          </div>
        </div>
      </CardHeader>
      <CardContent className="p-2">
        <div className="mb-1 flex items-center gap-3 px-1 text-[10px] text-muted-foreground">
          <span className="w-12 shrink-0">PID</span>
          <span className="min-w-0 flex-1">命令</span>
          <span className="w-14 shrink-0 text-right">CPU</span>
          <span className="w-14 shrink-0 text-right">MEM</span>
        </div>
        {filtered.length === 0 ? (
          <p className="py-4 text-center text-[11px] text-muted-foreground">
            没有匹配「{keyword}」的进程
          </p>
        ) : (
          filtered.map((proc) => (
            <div
              key={proc.pid}
              className="flex items-center gap-3 rounded px-1 py-0.5 text-xs hover:bg-accent/50"
            >
              <span className="w-12 shrink-0 font-mono text-muted-foreground">{proc.pid}</span>
              <span className="min-w-0 flex-1 truncate font-mono" title={proc.name}>
                {proc.name}
              </span>
              <span
                className={cn(
                  "w-14 shrink-0 text-right font-mono tabular-nums",
                  toneClass(proc.cpuPercent),
                )}
              >
                {proc.cpuPercent.toFixed(1)}%
              </span>
              <span className="w-14 shrink-0 text-right font-mono tabular-nums text-muted-foreground">
                {proc.memPercent.toFixed(1)}%
              </span>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}