import * as React from "react";
import { Group } from "@visx/group";
import { AreaClosed, LinePath } from "@visx/shape";
import { scaleLinear, scaleTime } from "@visx/scale";
import { curveMonotoneX } from "@visx/curve";
import { GridRows } from "@visx/grid";
import type { MonitorMetrics } from "@toolbox/contracts";
import { cn } from "@/lib/utils";
import { formatBytes } from "./format";

/**
 * 轻量趋势图。
 *
 * 用 visx 的三个原语（Group / shape / scale）手绘 SVG，
 * 不引入任何内置样式或图例 —— 颜色全部走 CSS 变量，
 * 因此深浅色与六套强调色都能自动适配。
 */

const PAD = { top: 8, right: 8, bottom: 18, left: 34 };

/** 通用折线/面积图。 */
function SparkArea({
  data,
  getValue,
  height = 96,
  color,
  formatValue,
  maxValue,
  fillId,
}: {
  data: MonitorMetrics[];
  getValue: (point: MonitorMetrics) => number;
  height?: number;
  color: string;
  formatValue: (value: number) => string;
  maxValue?: number;
  fillId: string;
}) {
  const containerRef = React.useRef<HTMLDivElement>(null);
  const [width, setWidth] = React.useState(0);

  React.useEffect(() => {
    const element = containerRef.current;
    if (!element) return;
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) setWidth(entry.contentRect.width);
    });
    observer.observe(element);
    setWidth(element.getBoundingClientRect().width);
    return () => observer.disconnect();
  }, []);

  const innerWidth = Math.max(0, width - PAD.left - PAD.right);
  const innerHeight = Math.max(0, height - PAD.top - PAD.bottom);

  const xScale = React.useMemo(() => {
    if (data.length === 0) return scaleTime({ domain: [new Date(0), new Date(1)], range: [0, innerWidth] });
    const first = data[0]!.timestamp;
    const last = data[data.length - 1]!.timestamp;
    return scaleTime({
      domain: [new Date(first), new Date(Math.max(last, first + 1))],
      range: [0, innerWidth],
    });
  }, [data, innerWidth]);

  const yScale = React.useMemo(() => {
    const max = maxValue ?? Math.max(1, ...data.map(getValue)) * 1.15;
    return scaleLinear({ domain: [0, max], range: [innerHeight, 0], nice: true });
  }, [data, getValue, maxValue, innerHeight]);

  if (!data.length) {
    return (
      <div
        ref={containerRef}
        className="grid place-items-center text-xs text-muted-foreground"
        style={{ height }}
      >
        等待数据…
      </div>
    );
  }

  const latest = data[data.length - 1]!;

  return (
    <div ref={containerRef} className="relative">
      <div className="mb-1 flex items-baseline justify-between">
        <span className="font-mono text-lg font-semibold tabular-nums">
          {formatValue(getValue(latest))}
        </span>
        <span className="text-[10px] text-muted-foreground">
          {data.length} 个采样点
        </span>
      </div>

      {innerWidth > 0 ? (
        <svg width={width} height={height} role="img" aria-label="趋势图">
          <defs>
            <linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.35} />
              <stop offset="100%" stopColor={color} stopOpacity={0.02} />
            </linearGradient>
          </defs>

          <Group left={PAD.left} top={PAD.top}>
            <GridRows
              scale={yScale}
              width={innerWidth}
              height={innerHeight}
              numTicks={3}
              stroke="currentColor"
              className="text-border"
              strokeOpacity={0.4}
              strokeDasharray="2,3"
            />

            <AreaClosed
              data={data}
              x={(point) => xScale(new Date(point.timestamp)) ?? 0}
              y={(point) => yScale(getValue(point)) ?? 0}
              yScale={yScale}
              curve={curveMonotoneX}
              fill={`url(#${fillId})`}
            />
            <LinePath
              data={data}
              x={(point) => xScale(new Date(point.timestamp)) ?? 0}
              y={(point) => yScale(getValue(point)) ?? 0}
              curve={curveMonotoneX}
              stroke={color}
              strokeWidth={1.5}
              strokeLinecap="round"
            />

            {/* Y 轴刻度 */}
            {yScale.ticks(3).map((tick) => (
              <text
                key={tick}
                x={-6}
                y={(yScale(tick) ?? 0) + 3}
                textAnchor="end"
                className="fill-muted-foreground text-[9px]"
              >
                {formatValue(tick)}
              </text>
            ))}
          </Group>
        </svg>
      ) : null}
    </div>
  );
}

/** CPU 趋势。 */
export function CpuChart({ data }: { data: MonitorMetrics[] }) {
  return (
    <SparkArea
      data={data}
      getValue={(point) => point.cpuPercent}
      maxValue={100}
      color="var(--chart-1)"
      fillId="cpu-fill"
      formatValue={(value) => `${value.toFixed(0)}%`}
    />
  );
}

/** 内存趋势（按百分比）。 */
export function MemoryChart({ data }: { data: MonitorMetrics[] }) {
  return (
    <SparkArea
      data={data}
      getValue={(point) =>
        point.memTotalBytes ? (point.memUsedBytes / point.memTotalBytes) * 100 : 0
      }
      maxValue={100}
      color="var(--chart-2)"
      fillId="mem-fill"
      formatValue={(value) => `${value.toFixed(0)}%`}
    />
  );
}

/** 网络吞吐趋势（上下行两条线，单位 MiB/s）。 */
export function NetworkChart({ data }: { data: MonitorMetrics[] }) {
  const containerRef = React.useRef<HTMLDivElement>(null);
  const [width, setWidth] = React.useState(0);

  React.useEffect(() => {
    const element = containerRef.current;
    if (!element) return;
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) setWidth(entry.contentRect.width);
    });
    observer.observe(element);
    setWidth(element.getBoundingClientRect().width);
    return () => observer.disconnect();
  }, []);

  const height = 96;
  const innerWidth = Math.max(0, width - PAD.left - PAD.right);
  const innerHeight = Math.max(0, height - PAD.top - PAD.bottom);

  const toMiB = (bytes: number) => bytes / 1024 / 1024;

  const xScale = React.useMemo(() => {
    if (data.length === 0) return scaleTime({ domain: [new Date(0), new Date(1)], range: [0, innerWidth] });
    const first = data[0]!.timestamp;
    const last = data[data.length - 1]!.timestamp;
    return scaleTime({
      domain: [new Date(first), new Date(Math.max(last, first + 1))],
      range: [0, innerWidth],
    });
  }, [data, innerWidth]);

  const yScale = React.useMemo(() => {
    const max = Math.max(
      0.1,
      ...data.map((point) => Math.max(toMiB(point.netRxBytesPerSec), toMiB(point.netTxBytesPerSec))),
    );
    return scaleLinear({ domain: [0, max * 1.2], range: [innerHeight, 0], nice: true });
  }, [data, innerHeight]);

  if (!data.length) {
    return (
      <div ref={containerRef} className="grid place-items-center text-xs text-muted-foreground" style={{ height }}>
        等待数据…
      </div>
    );
  }

  const latest = data[data.length - 1]!;

  return (
    <div ref={containerRef}>
      <div className="mb-1 flex items-baseline gap-3 text-[11px]">
        <span className="text-[var(--chart-3)]">
          ↓ {toMiB(latest.netRxBytesPerSec).toFixed(2)} MiB/s
        </span>
        <span className="text-[var(--chart-4)]">
          ↑ {toMiB(latest.netTxBytesPerSec).toFixed(2)} MiB/s
        </span>
      </div>

      {innerWidth > 0 ? (
        <svg width={width} height={height} role="img" aria-label="网络趋势">
          <Group left={PAD.left} top={PAD.top}>
            <GridRows
              scale={yScale}
              width={innerWidth}
              height={innerHeight}
              numTicks={3}
              stroke="currentColor"
              className="text-border"
              strokeOpacity={0.4}
              strokeDasharray="2,3"
            />
            <LinePath
              data={data}
              x={(point) => xScale(new Date(point.timestamp)) ?? 0}
              y={(point) => yScale(toMiB(point.netRxBytesPerSec)) ?? 0}
              curve={curveMonotoneX}
              stroke="var(--chart-3)"
              strokeWidth={1.5}
            />
            <LinePath
              data={data}
              x={(point) => xScale(new Date(point.timestamp)) ?? 0}
              y={(point) => yScale(toMiB(point.netTxBytesPerSec)) ?? 0}
              curve={curveMonotoneX}
              stroke="var(--chart-4)"
              strokeWidth={1.5}
            />
            {yScale.ticks(3).map((tick) => (
              <text
                key={tick}
                x={-6}
                y={(yScale(tick) ?? 0) + 3}
                textAnchor="end"
                className="fill-muted-foreground text-[9px]"
              >
                {tick.toFixed(1)}
              </text>
            ))}
          </Group>
        </svg>
      ) : null}
    </div>
  );
}

/** GPU 四个指标分别成图。 */
export type GpuMetric = "util" | "memory" | "temp" | "power";

/**
 * 四个指标各自的颜色。
 *
 * 颜色只用来区分「指标类型」，同一张图里的多块卡仍靠位置与
 * 右上角数值区分，避免二次编码造成误读。
 */
const GPU_METRIC_META: Record<
  GpuMetric,
  { label: string; unit: string; max?: number; color: string; fill: string }
> = {
  util: { label: "使用率", unit: "%", max: 100, color: "var(--chart-1)", fill: "gpu-util" },
  memory: { label: "显存", unit: "%", max: 100, color: "var(--chart-2)", fill: "gpu-mem" },
  temp: { label: "温度", unit: "°C", color: "var(--chart-4)", fill: "gpu-temp" },
  power: { label: "功耗", unit: "W", color: "var(--chart-5)", fill: "gpu-power" },
};

function gpuValue(
  point: MonitorMetrics,
  gpuIndex: number,
  metric: GpuMetric,
): number {
  const gpu = point.gpus[gpuIndex];
  if (!gpu) return 0;
  switch (metric) {
    case "util":
      return gpu.utilPercent;
    case "memory":
      return gpu.memTotalMiB > 0 ? (gpu.memUsedMiB / gpu.memTotalMiB) * 100 : 0;
    case "temp":
      return gpu.tempC;
    case "power":
      return gpu.powerWatts;
  }
}

/** 单个 GPU 指标的趋势图（多卡各一条线）。 */
export function GpuChart({
  data,
  metric,
}: {
  data: MonitorMetrics[];
  metric: GpuMetric;
}) {
  const containerRef = React.useRef<HTMLDivElement>(null);
  const [width, setWidth] = React.useState(0);

  React.useEffect(() => {
    const element = containerRef.current;
    if (!element) return;
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) setWidth(entry.contentRect.width);
    });
    observer.observe(element);
    setWidth(element.getBoundingClientRect().width);
    return () => observer.disconnect();
  }, []);

  const meta = GPU_METRIC_META[metric];
  const height = 72;
  const innerWidth = Math.max(0, width - PAD.left - PAD.right);
  const innerHeight = Math.max(0, height - PAD.top - PAD.bottom);

  const gpuCount = Math.max(0, ...data.map((point) => point.gpus.length));

  const xScale = React.useMemo(() => {
    if (data.length === 0)
      return scaleTime({ domain: [new Date(0), new Date(1)], range: [0, innerWidth] });
    const first = data[0]!.timestamp;
    const last = data[data.length - 1]!.timestamp;
    return scaleTime({
      domain: [new Date(first), new Date(Math.max(last, first + 1))],
      range: [0, innerWidth],
    });
  }, [data, innerWidth]);

  const yScale = React.useMemo(() => {
    const peak = Math.max(1, ...data.flatMap((point) =>
      point.gpus.map((_, index) => gpuValue(point, index, metric)),
    ));
    const max = meta.max ?? Math.max(1, peak * 1.15);
    return scaleLinear({ domain: [0, max], range: [innerHeight, 0] });
  }, [data, metric, meta.max, innerHeight]);

  if (!data.length || gpuCount === 0) {
    return (
      <div
        ref={containerRef}
        className="grid place-items-center text-[10px] text-muted-foreground"
        style={{ height }}
      >
        无数据
      </div>
    );
  }

  const latest = data[data.length - 1]!;

  return (
    <div ref={containerRef}>
      <div className="mb-0.5 flex items-baseline justify-between">
        <span
          className="flex items-center gap-1 text-[10px] font-medium"
          style={{ color: meta.color }}
        >
          <span
            className="h-1.5 w-1.5 rounded-full"
            style={{ backgroundColor: meta.color }}
          />
          {meta.label}
        </span>
        <span className="font-mono text-[9px] tabular-nums" style={{ color: meta.color }}>
          {latest.gpus
            .map((gpu, index) => {
              const value = gpuValue(latest, index, metric).toFixed(0);
              return gpuCount > 1 ? `#${gpu.index} ${value}${meta.unit}` : `${value}${meta.unit}`;
            })
            .join("  ")}
        </span>
      </div>

      {innerWidth > 0 ? (
        <svg width={width} height={height} role="img" aria-label={`GPU ${meta.label}趋势`}>
          <defs>
            <linearGradient id={meta.fill} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={meta.color} stopOpacity={0.28} />
              <stop offset="100%" stopColor={meta.color} stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <Group left={PAD.left} top={PAD.top}>
            <GridRows
              scale={yScale}
              width={innerWidth}
              height={innerHeight}
              numTicks={2}
              stroke="currentColor"
              className="text-border"
              strokeOpacity={0.4}
              strokeDasharray="2,3"
            />
            {gpuCount === 1 ? (
              <AreaClosed
                data={data.filter((point) => point.gpus[0])}
                x={(point) => xScale(new Date(point.timestamp)) ?? 0}
                y={(point) => yScale(gpuValue(point, 0, metric)) ?? 0}
                yScale={yScale}
                curve={curveMonotoneX}
                fill={`url(#${meta.fill})`}
              />
            ) : null}
            {Array.from({ length: gpuCount }).map((_, gpuIndex) => (
              <LinePath
                key={gpuIndex}
                data={data.filter((point) => point.gpus[gpuIndex])}
                x={(point) => xScale(new Date(point.timestamp)) ?? 0}
                y={(point) => yScale(gpuValue(point, gpuIndex, metric)) ?? 0}
                curve={curveMonotoneX}
                stroke={meta.color}
                strokeWidth={1.5}
                strokeDasharray={gpuCount > 1 ? `${4 + gpuIndex * 3} 3` : undefined}
              />
            ))}
            {yScale.ticks(2).map((tick) => (
              <text
                key={tick}
                x={-5}
                y={(yScale(tick) ?? 0) + 3}
                textAnchor="end"
                className="fill-muted-foreground text-[8px]"
              >
                {tick.toFixed(0)}
              </text>
            ))}
          </Group>
        </svg>
      ) : null}
    </div>
  );
}

/** GPU 四联图。 */
export function GpuCharts({ data }: { data: MonitorMetrics[] }) {
  const metrics: GpuMetric[] = ["util", "memory", "temp", "power"];
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {metrics.map((metric) => (
        <GpuChart key={metric} data={data} metric={metric} />
      ))}
    </div>
  );
}

/** NPU 指标。 */
export type NpuMetric = "aicore" | "hbm" | "temp" | "power";

const NPU_METRIC_META: Record<
  NpuMetric,
  { label: string; unit: string; max?: number; color: string; fill: string }
> = {
  aicore: { label: "AI Core", unit: "%", max: 100, color: "var(--chart-1)", fill: "npu-ai" },
  hbm: { label: "HBM", unit: "%", max: 100, color: "var(--chart-2)", fill: "npu-hbm" },
  temp: { label: "温度", unit: "°C", color: "var(--chart-4)", fill: "npu-temp" },
  power: { label: "功耗", unit: "W", color: "var(--chart-5)", fill: "npu-power" },
};

function npuValue(point: MonitorMetrics, index: number, metric: NpuMetric): number {
  const npu = point.npus[index];
  if (!npu) return 0;
  switch (metric) {
    case "aicore":
      return npu.aiCorePercent;
    case "hbm":
      return npu.hbmPercent;
    case "temp":
      return npu.tempC;
    case "power":
      return npu.powerWatts;
  }
}

/** 单个 NPU 指标趋势图（多卡多线）。 */
function NpuChart({ data, metric }: { data: MonitorMetrics[]; metric: NpuMetric }) {
  const containerRef = React.useRef<HTMLDivElement>(null);
  const [width, setWidth] = React.useState(0);

  React.useEffect(() => {
    const element = containerRef.current;
    if (!element) return;
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) setWidth(entry.contentRect.width);
    });
    observer.observe(element);
    setWidth(element.getBoundingClientRect().width);
    return () => observer.disconnect();
  }, []);

  const meta = NPU_METRIC_META[metric];
  const height = 72;
  const innerWidth = Math.max(0, width - PAD.left - PAD.right);
  const innerHeight = Math.max(0, height - PAD.top - PAD.bottom);

  const count = Math.max(0, ...data.map((point) => point.npus.length));

  const xScale = React.useMemo(() => {
    if (data.length === 0)
      return scaleTime({ domain: [new Date(0), new Date(1)], range: [0, innerWidth] });
    const first = data[0]!.timestamp;
    const last = data[data.length - 1]!.timestamp;
    return scaleTime({
      domain: [new Date(first), new Date(Math.max(last, first + 1))],
      range: [0, innerWidth],
    });
  }, [data, innerWidth]);

  const yScale = React.useMemo(() => {
    const peak = Math.max(
      1,
      ...data.flatMap((point) => point.npus.map((_, index) => npuValue(point, index, metric))),
    );
    const max = meta.max ?? Math.max(1, peak * 1.15);
    return scaleLinear({ domain: [0, max], range: [innerHeight, 0] });
  }, [data, metric, meta.max, innerHeight]);

  if (!data.length || count === 0) {
    return (
      <div
        ref={containerRef}
        className="grid place-items-center text-[10px] text-muted-foreground"
        style={{ height }}
      >
        无数据
      </div>
    );
  }

  const latest = data[data.length - 1]!;

  return (
    <div ref={containerRef}>
      <div className="mb-0.5 flex items-baseline justify-between">
        <span
          className="flex items-center gap-1 text-[10px] font-medium"
          style={{ color: meta.color }}
        >
          <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: meta.color }} />
          {meta.label}
        </span>
        <span className="font-mono text-[9px] tabular-nums" style={{ color: meta.color }}>
          {latest.npus
            .map((npu, index) => {
              const value = npuValue(latest, index, metric).toFixed(0);
              return count > 1 ? `#${npu.index} ${value}${meta.unit}` : `${value}${meta.unit}`;
            })
            .join("  ")}
        </span>
      </div>

      {innerWidth > 0 ? (
        <svg width={width} height={height} role="img" aria-label={`NPU ${meta.label}趋势`}>
          <defs>
            <linearGradient id={meta.fill} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={meta.color} stopOpacity={0.28} />
              <stop offset="100%" stopColor={meta.color} stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <Group left={PAD.left} top={PAD.top}>
            <GridRows
              scale={yScale}
              width={innerWidth}
              height={innerHeight}
              numTicks={2}
              stroke="currentColor"
              className="text-border"
              strokeOpacity={0.4}
              strokeDasharray="2,3"
            />
            {count === 1 ? (
              <AreaClosed
                data={data.filter((point) => point.npus[0])}
                x={(point) => xScale(new Date(point.timestamp)) ?? 0}
                y={(point) => yScale(npuValue(point, 0, metric)) ?? 0}
                yScale={yScale}
                curve={curveMonotoneX}
                fill={`url(#${meta.fill})`}
              />
            ) : null}
            {Array.from({ length: count }).map((_, index) => (
              <LinePath
                key={index}
                data={data.filter((point) => point.npus[index])}
                x={(point) => xScale(new Date(point.timestamp)) ?? 0}
                y={(point) => yScale(npuValue(point, index, metric)) ?? 0}
                curve={curveMonotoneX}
                stroke={meta.color}
                strokeWidth={1.5}
                strokeDasharray={count > 1 ? `${4 + index * 3} 3` : undefined}
              />
            ))}
            {yScale.ticks(2).map((tick) => (
              <text
                key={tick}
                x={-5}
                y={(yScale(tick) ?? 0) + 3}
                textAnchor="end"
                className="fill-muted-foreground text-[8px]"
              >
                {tick.toFixed(0)}
              </text>
            ))}
          </Group>
        </svg>
      ) : null}
    </div>
  );
}

/** NPU 四联图。 */
export function NpuCharts({ data }: { data: MonitorMetrics[] }) {
  const metrics: NpuMetric[] = ["aicore", "hbm", "temp", "power"];
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {metrics.map((metric) => (
        <NpuChart key={metric} data={data} metric={metric} />
      ))}
    </div>
  );
}

/**
 * 磁盘使用：容量条 + 明细。
 *
 * 参考 Grafana / node_exporter 仪表盘的做法：
 * - 主视觉是「已用 / 总量」的比例条，宽度代表容量占比
 * - 右侧给出百分比，颜色只在接近满盘时才警示
 * - 挂载点是等宽字体，便于扫描一列路径
 */
export function DiskBars({ disks }: { disks: MonitorMetrics["disks"] }) {
  return (
    <div className="space-y-3">
      {disks.map((disk) => {
        const percent = disk.totalBytes ? (disk.usedBytes / disk.totalBytes) * 100 : 0;
        const free = Math.max(0, disk.totalBytes - disk.usedBytes);
        const level =
          percent >= 90 ? "critical" : percent >= 75 ? "warning" : "normal";

        return (
          <div key={disk.mount} className="space-y-1">
            <div className="flex items-baseline justify-between gap-3">
              <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-foreground">
                {disk.mount}
              </span>
              <span className="shrink-0 font-mono text-[11px] tabular-nums text-muted-foreground">
                {formatBytes(disk.usedBytes)}
                <span className="opacity-50"> / </span>
                {formatBytes(disk.totalBytes)}
              </span>
              <span
                className={cn(
                  "w-10 shrink-0 text-right font-mono text-[11px] tabular-nums",
                  level === "critical"
                    ? "text-red-600 dark:text-red-400"
                    : level === "warning"
                      ? "text-orange-600 dark:text-orange-400"
                      : "text-muted-foreground",
                )}
              >
                {percent.toFixed(0)}%
              </span>
            </div>

            {/* 容量条：整条代表总容量，填充代表已用 */}
            <div className="h-2 overflow-hidden rounded-sm bg-muted">
              <div
                className={cn(
                  "h-full transition-all duration-500",
                  level === "critical"
                    ? "bg-red-500"
                    : level === "warning"
                      ? "bg-orange-500"
                      : "bg-[var(--chart-5)]",
                )}
                style={{ width: `${Math.min(100, percent)}%` }}
              />
            </div>

            <p className="text-[10px] text-muted-foreground/70">
              剩余 {formatBytes(free)}
            </p>
          </div>
        );
      })}
    </div>
  );
}

/** 字节格式化（供外部复用）。 */