import * as React from "react";
import { Activity, Cpu, HardDrive, MemoryStick, Network, Server, Thermometer } from "lucide-react";
import type { MonitorMetrics, ServerInfo } from "@toolbox/contracts";
import { cn } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

/** 字节格式化。 */
function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
  const value = bytes / 1024 ** index;
  return `${value >= 100 ? value.toFixed(0) : value.toFixed(1)} ${units[index]}`;
}

/** 速率格式化。 */
function formatRate(bytesPerSec: number): string {
  return `${formatBytes(bytesPerSec)}/s`;
}

/** 使用率对应的颜色。 */
function toneFor(percent: number): string {
  if (percent >= 90) return "bg-red-500";
  if (percent >= 75) return "bg-orange-500";
  if (percent >= 50) return "bg-amber-500";
  return "bg-emerald-500";
}

/** 横向进度条。 */
function Meter({
  label,
  value,
  detail,
  icon: Icon,
}: {
  label: string;
  value: number;
  detail: string;
  icon: React.ComponentType<{ className?: string }>;
}) {
  const clamped = Math.min(100, Math.max(0, value));
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between text-xs">
        <span className="flex items-center gap-1.5 text-muted-foreground">
          <Icon className="h-3.5 w-3.5" />
          {label}
        </span>
        <span className="font-mono tabular-nums text-foreground">{detail}</span>
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-muted">
        <div
          className={cn("h-full rounded-full transition-all duration-500", toneFor(clamped))}
          style={{ width: `${clamped}%` }}
        />
      </div>
    </div>
  );
}

/** 监控面板。 */
export function MonitorPanel({
  metrics,
  info,
  loading,
  error,
}: {
  metrics: MonitorMetrics | null;
  info: ServerInfo | null;
  loading: boolean;
  error: string | null;
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
          <Skeleton key={index} className="h-28 w-full" />
        ))}
      </div>
    );
  }

  if (!metrics) {
    return (
      <p className="py-8 text-center text-sm text-muted-foreground">正在采集第一组数据…</p>
    );
  }

  const memPercent = metrics.memTotalBytes
    ? (metrics.memUsedBytes / metrics.memTotalBytes) * 100
    : 0;
  const swapPercent = metrics.swapTotalBytes
    ? (metrics.swapUsedBytes / metrics.swapTotalBytes) * 100
    : 0;

  return (
    <div className="space-y-3">
      {/* 服务器信息 */}
      {info ? (
        <Card>
          <CardContent className="flex flex-wrap items-center gap-x-6 gap-y-1.5 p-3 text-xs">
            <span className="flex items-center gap-1.5 font-medium">
              <Server className="h-3.5 w-3.5 text-primary" />
              {info.hostname || "未知主机"}
            </span>
            {info.ip ? <span className="text-muted-foreground">{info.ip}</span> : null}
            {info.os ? <span className="text-muted-foreground">{info.os}</span> : null}
            {info.kernel ? (
              <span className="text-muted-foreground">kernel {info.kernel}</span>
            ) : null}
            {info.cpuModel ? (
              <span className="max-w-[22rem] truncate text-muted-foreground">
                {info.cpuModel} · {info.cpuCores} 核
              </span>
            ) : null}
          </CardContent>
        </Card>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2">
        {/* CPU / 内存 */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-xs font-medium text-muted-foreground">资源</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <Meter
              label="CPU"
              icon={Cpu}
              value={metrics.cpuPercent}
              detail={`${metrics.cpuPercent.toFixed(1)}% · ${metrics.cpuCores} 核`}
            />
            <Meter
              label="内存"
              icon={MemoryStick}
              value={memPercent}
              detail={`${formatBytes(metrics.memUsedBytes)} / ${formatBytes(metrics.memTotalBytes)}`}
            />
            {metrics.swapTotalBytes > 0 ? (
              <Meter
                label="Swap"
                icon={MemoryStick}
                value={swapPercent}
                detail={`${formatBytes(metrics.swapUsedBytes)} / ${formatBytes(metrics.swapTotalBytes)}`}
              />
            ) : null}
          </CardContent>
        </Card>

        {/* 负载 / 网络 */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-xs font-medium text-muted-foreground">
              负载与网络
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-xs">
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <Activity className="h-3.5 w-3.5" />
                负载
              </span>
              <span className="font-mono tabular-nums">
                {metrics.load1.toFixed(2)} / {metrics.load5.toFixed(2)} /{" "}
                {metrics.load15.toFixed(2)}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <Network className="h-3.5 w-3.5" />
                下行
              </span>
              <span className="font-mono tabular-nums text-emerald-600 dark:text-emerald-400">
                {formatRate(metrics.netRxBytesPerSec)}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <Network className="h-3.5 w-3.5" />
                上行
              </span>
              <span className="font-mono tabular-nums text-sky-600 dark:text-sky-400">
                {formatRate(metrics.netTxBytesPerSec)}
              </span>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* 磁盘 */}
      {metrics.disks.length > 0 ? (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-xs font-medium text-muted-foreground">磁盘</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2.5">
            {metrics.disks.map((disk) => {
              const percent = disk.totalBytes ? (disk.usedBytes / disk.totalBytes) * 100 : 0;
              return (
                <Meter
                  key={disk.mount}
                  label={disk.mount}
                  icon={HardDrive}
                  value={percent}
                  detail={`${formatBytes(disk.usedBytes)} / ${formatBytes(disk.totalBytes)}`}
                />
              );
            })}
          </CardContent>
        </Card>
      ) : null}

      {/* GPU */}
      {metrics.gpus.length > 0 ? (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
              <Thermometer className="h-3.5 w-3.5" />
              GPU
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
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
                    className={cn("h-full rounded-full", toneFor(gpu.utilPercent))}
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
          <CardHeader className="pb-2">
            <CardTitle className="text-xs font-medium text-muted-foreground">NPU（昇腾）</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-xs">
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
          <CardHeader className="pb-2">
            <CardTitle className="text-xs font-medium text-muted-foreground">
              CPU 占用 TOP
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1">
            {metrics.processes.map((proc) => (
              <div
                key={proc.pid}
                className="flex items-center gap-3 rounded px-1 py-1 text-xs hover:bg-accent/50"
              >
                <span className="w-12 shrink-0 font-mono text-muted-foreground">{proc.pid}</span>
                <span className="min-w-0 flex-1 truncate font-mono" title={proc.name}>
                  {proc.name}
                </span>
                <span className="w-14 shrink-0 text-right font-mono tabular-nums text-orange-600 dark:text-orange-400">
                  {proc.cpuPercent.toFixed(1)}%
                </span>
                <span className="w-14 shrink-0 text-right font-mono tabular-nums text-sky-600 dark:text-sky-400">
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
