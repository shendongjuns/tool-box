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

/** GPU 使用率趋势（多卡各一条线）。 */
export function GpuChart({ data }: { data: MonitorMetrics[] }) {
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

  const yScale = React.useMemo(
    () => scaleLinear({ domain: [0, 100], range: [innerHeight, 0] }),
    [innerHeight],
  );

  if (!data.length || gpuCount === 0) {
    return (
      <div
        ref={containerRef}
        className="grid place-items-center text-xs text-muted-foreground"
        style={{ height }}
      >
        未检测到 GPU
      </div>
    );
  }

  const latest = data[data.length - 1]!;
  const colors = ["var(--chart-1)", "var(--chart-2)", "var(--chart-3)", "var(--chart-4)"];

  return (
    <div ref={containerRef}>
      <div className="mb-1 flex flex-wrap items-baseline gap-x-3 gap-y-0.5 text-[10px]">
        {latest.gpus.map((gpu, index) => (
          <span key={gpu.index} style={{ color: colors[index % colors.length] }}>
            #{gpu.index} {gpu.utilPercent.toFixed(0)}% · {gpu.tempC.toFixed(0)}°C
          </span>
        ))}
      </div>

      {innerWidth > 0 ? (
        <svg width={width} height={height} role="img" aria-label="GPU 使用率趋势">
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
            {Array.from({ length: gpuCount }).map((_, gpuIndex) => (
              <LinePath
                key={gpuIndex}
                data={data.filter((point) => point.gpus[gpuIndex])}
                x={(point) => xScale(new Date(point.timestamp)) ?? 0}
                y={(point) => yScale(point.gpus[gpuIndex]?.utilPercent ?? 0) ?? 0}
                curve={curveMonotoneX}
                stroke={colors[gpuIndex % colors.length]}
                strokeWidth={1.5}
              />
            ))}
            {[0, 50, 100].map((tick) => (
              <text
                key={tick}
                x={-6}
                y={(yScale(tick) ?? 0) + 3}
                textAnchor="end"
                className="fill-muted-foreground text-[9px]"
              >
                {tick}%
              </text>
            ))}
          </Group>
        </svg>
      ) : null}
    </div>
  );
}

/** 磁盘使用率条形组。 */
export function DiskBars({ disks }: { disks: MonitorMetrics["disks"] }) {
  return (
    <div className="space-y-2.5">
      {disks.map((disk) => {
        const percent = disk.totalBytes ? (disk.usedBytes / disk.totalBytes) * 100 : 0;
        return (
          <div key={disk.mount} className="space-y-1">
            <div className="flex items-center justify-between text-[11px]">
              <span className="truncate font-mono text-muted-foreground">{disk.mount}</span>
              <span className="shrink-0 tabular-nums">
                {formatBytes(disk.usedBytes)} / {formatBytes(disk.totalBytes)}
              </span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-muted">
              <div
                className={cn(
                  "h-full rounded-full transition-all duration-500",
                  percent >= 90
                    ? "bg-red-500"
                    : percent >= 75
                      ? "bg-orange-500"
                      : "bg-[var(--chart-5)]",
                )}
                style={{ width: `${Math.min(100, percent)}%` }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** 字节格式化（供外部复用）。 */