/**
 * 图表悬浮提示。
 *
 * visx 只提供原语，tooltip 要自己画。做法：
 * - 用 SVG 的 mousemove 拿到相对坐标
 * - 二分/线性找到最近的时间点
 * - 用 HTML 绝对定位的浮层展示（比 SVG text 更容易做样式）
 */
/** 判定为「贴近边缘」的阈值（像素）。 */
const EDGE_PX = 96;

export interface TooltipState {
  x: number;
  y: number;
  label: string;
  rows: { color: string; name: string; value: string }[];
}

export function ChartTooltip({
  state,
  containerWidth,
}: {
  state: TooltipState | null;
  /** 容器宽度，用于判断浮层是否贴边 */
  containerWidth: number;
}) {
  if (!state) return null;

  // 靠近左右边缘时改为贴边对齐，避免半个浮层探出容器撑出滚动条
  const nearLeft = state.x < EDGE_PX;
  const nearRight = state.x > containerWidth - EDGE_PX;
  const shift = nearLeft ? "0" : nearRight ? "-100%" : "-50%";

  return (
    /*
     * 定位说明（避免溢出导致横向滚动条）：
     * - 不用 translate(-50%)：那会让浮层左半边探出容器，
     *   图表容器又是 relative 无裁剪，鼠标靠右时就会撑出滚动条；
     * - 改为 clamp：把 left 限制在 [0, 100%] 并用 max-width 收窄，
     *   浮层永远落在容器内部；
     * - clamp 用 CSS 变量 + calc 实现，不依赖测量 DOM。
     */
    <div
      className="pointer-events-none absolute z-20 w-max max-w-[12rem] rounded-md border border-border bg-card/95 px-2 py-1.5 text-[10px] shadow-lg backdrop-blur-sm"
      style={{
        left: `clamp(0px, ${state.x}px, 100%)`,
        top: state.y,
        transform: `translateY(-115%) translateX(${shift})`,
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