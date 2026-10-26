import * as React from "react";
import {
  Activity,
  Cpu,
  HardDrive,
  MemoryStick,
  Network,
  Server,
  Thermometer,
} from "lucide-react";
import type { MonitorMetrics, ServerInfo } from "@toolbox/contracts";
import { cn } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { CpuChart, DiskBars, MemoryChart, NetworkChart } from "./charts";
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

      <div className="grid gap-3 lg:grid-cols-2">
        <MetricCard
          label="网络"
          icon={Network}
          value={`${(metrics.netRxBytesPerSec / 1048576).toFixed(2)} MiB/s`}
          sub={`上行 ${(metrics.netTxBytesPerSec / 1048576).toFixed(2)} MiB/s`}
        >
          <NetworkChart data={history} />
        </MetricCard>

        {/* 负载与 Swap */}
        <Card>
          <CardHeader className="p-3 pb-1">
            <CardTitle className="flex items-center gap-1.5 text-[11px] font-medium text-muted-foreground">
              <Activity className="h-3.5 w-3.5" />
              负载与交换
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 p-3 pt-1 text-xs">
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">1 / 5 / 15 分钟</span>
              <span className="font-mono tabular-nums">
                {metrics.load1.toFixed(2)} / {metrics.load5.toFixed(2)} /{" "}
                {metrics.load15.toFixed(2)}
              </span>
            </div>
            {metrics.swapTotalBytes > 0 ? (
              <>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Swap</span>
                  <span className="font-mono tabular-nums">
                    {formatBytes(metrics.swapUsedBytes)} / {formatBytes(metrics.swapTotalBytes)}
                  </span>
                </div>
                <div className="h-1.5 overflow-hidden rounded-full bg-muted">
                  <div
                    className="h-full rounded-full bg-[var(--chart-5)] transition-all duration-500"
                    style={{
                      width: `${Math.min(
                        100,
                        (metrics.swapUsedBytes / metrics.swapTotalBytes) * 100,
                      )}%`,
                    }}
                  />
                </div>
              </>
            ) : (
              <p className="text-[11px] text-muted-foreground">未启用 Swap</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* 磁盘 */}
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

      {/* GPU */}
      {metrics.gpus.length > 0 ? (
        <Card>
          <CardHeader className="p-3 pb-1">
            <CardTitle className="flex items-center gap-1.5 text-[11px] font-medium text-muted-foreground">
              <Thermometer className="h-3.5 w-3.5" />
              GPU
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 p-3 pt-2">
            {metrics.gpus.map((gpu) => (
              <div key={gpu.index} className="space-y-1.5">
                <div className="flex items-center justify-between text-xs">
                  <span className="truncate font-medium">{gpu.name}</span>
                  <span className="shrink-0 font-mono tabular-nums text-muted-foreground">
                    {gpu.utilPercent.toFixed(0)}% · {gpu.memUsedMiB}/{gpu.memTotalMiB} MiB ·{" "}
                    {gpu.tempC.toFixed(0)}°C · {gpu.powerWatts.toFixed(0)}W
                  </span>
                </div>
                <div className="h-1.5 overflow-hidden rounded-full bg-muted">
                  <div
                    className={cn(
                      "h-full rounded-full transition-all",
                      gpu.utilPercent >= 90
                        ? "bg-red-500"
                        : gpu.utilPercent >= 70
                          ? "bg-orange-500"
                          : "bg-[var(--chart-1)]",
                    )}
                    style={{ width: `${Math.min(100, gpu.utilPercent)}%` }}
                  />
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      ) : null}

      {/* NPU */}
      {metrics.npus.length > 0 ? (
        <Card>
          <CardHeader className="p-3 pb-1">
            <CardTitle className="text-[11px] font-medium text-muted-foreground">
              NPU（昇腾）
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 p-3 pt-1 text-xs">
            {metrics.npus.map((npu) => (
              <div key={npu.index} className="flex items-center justify-between gap-3">
                <span className="flex items-center gap-1.5">
                  <span className="font-mono text-muted-foreground">#{npu.index}</span>
                  <span className="truncate font-medium">{npu.name}</span>
                </span>
                <span className="shrink-0 font-mono tabular-nums text-muted-foreground">
                  AI {npu.aiCorePercent.toFixed(0)}% · HBM {npu.hbmPercent.toFixed(0)}% ·{" "}
                  {npu.tempC.toFixed(0)}°C · {npu.powerWatts.toFixed(0)}W
                </span>
                <span
                  className={cn(
                    "shrink-0 rounded px-1.5 py-0.5 text-[10px] font-medium",
                    /ok/i.test(npu.health)
                      ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400"
                      : "bg-amber-500/15 text-amber-600 dark:text-amber-400",
                  )}
                >
                  {npu.health}
                </span>
              </div>
            ))}
          </CardContent>
        </Card>
      ) : null}

      {/* 进程 */}
      {metrics.processes.length > 0 ? (
        <Card>
          <CardHeader className="p-3 pb-1">
            <CardTitle className="text-[11px] font-medium text-muted-foreground">
              CPU 占用 TOP
            </CardTitle>
          </CardHeader>
          <CardContent className="p-2">
            <div className="mb-1 flex items-center gap-3 px-1 text-[10px] text-muted-foreground">
              <span className="w-12 shrink-0">PID</span>
              <span className="min-w-0 flex-1">命令</span>
              <span className="w-14 shrink-0 text-right">CPU</span>
              <span className="w-14 shrink-0 text-right">MEM</span>
            </div>
            {metrics.processes.map((proc) => (
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
            ))}
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}