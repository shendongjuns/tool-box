/**
 * 图表悬浮提示。
 *
 * visx 只提供原语，tooltip 要自己画。做法：
 * - 用 SVG 的 mousemove 拿到相对坐标
 * - 二分/线性找到最近的时间点
 * - 用 HTML 绝对定位的浮层展示（比 SVG text 更容易做样式）
 */
export interface TooltipState {
  x: number;
  y: number;
  label: string;
  rows: { color: string; name: string; value: string }[];
}

export function ChartTooltip({ state }: { state: TooltipState | null }) {
  if (!state) return null;

  return (
    <div
      className="pointer-events-none absolute z-20 min-w-[8rem] rounded-md border border-border bg-card/95 px-2 py-1.5 text-[10px] shadow-lg backdrop-blur-sm"
      style={{
        left: state.x,
        top: state.y,
        transform: "translate(-50%, -115%)",
      }}
    >
      <div className="mb-1 font-medium text-muted-foreground">{state.label}</div>
      <div className="space-y-0.5">
        {state.rows.map((row) => (
          <div key={row.name} className="flex items-center justify-between gap-3">
            <span className="flex items-center gap-1 text-muted-foreground">
              <span
                className="inline-block h-1.5 w-1.5 rounded-full"
                style={{ backgroundColor: row.color }}
              />
              {row.name}
            </span>
            <span className="font-mono tabular-nums text-foreground">{row.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
