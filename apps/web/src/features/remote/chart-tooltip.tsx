import { createPortal } from "react-dom";

/**
 * 图表悬浮提示。
 *
 * 关键决策：用 **position: fixed + portal 到 body**，而不是容器内 absolute。
 *
 * 原因：图表容器为了防横向滚动条加了 overflow 裁剪，
 * absolute 浮层只要超出容器边界（比如落在最上方的数据点上方）就会被裁掉，
 * 信息展示不全。fixed + portal 完全脱离祖先的 overflow 影响，
 * 同时用视口坐标自己处理贴边，不会撑出滚动条。
 */

/** 浮层与鼠标点的间距。 */
const OFFSET = 12;
/** 估算浮层高度，用于判断上方是否放得下。 */
const ESTIMATED_HEIGHT = 72;
/** 贴边留白。 */
const MARGIN = 8;

export interface TooltipState {
  /** 容器内坐标 —— 画竖向准线用 */
  x: number;
  y: number;
  /** 视口坐标 —— 浮层定位用 */
  clientX: number;
  clientY: number;
  label: string;
  rows: { color: string; name: string; value: string }[];
}

export function ChartTooltip({ state }: { state: TooltipState | null }) {
  if (!state || typeof document === "undefined") return null;

  const { clientX, clientY } = state;
  const viewportWidth = window.innerWidth;

  /*
   * 垂直方向：默认放在点的上方；上方空间不够就翻到下方。
   * 这样即使数据点在图表最顶部，浮层也不会跑出视口。
   */
  const showBelow = clientY - ESTIMATED_HEIGHT - OFFSET < MARGIN;
  const top = showBelow ? clientY + OFFSET : clientY - ESTIMATED_HEIGHT - OFFSET;

  /*
   * 水平方向：按剩余空间切换对齐，
   * 保证浮层左右边缘都不超出视口。
   */
  const nearLeft = clientX < 110;
  const nearRight = clientX > viewportWidth - 110;
  const shift = nearLeft ? "0" : nearRight ? "-100%" : "-50%";
  const left = Math.min(Math.max(clientX, MARGIN), viewportWidth - MARGIN);

  return createPortal(
    <div
      className="pointer-events-none fixed z-[9999] w-max max-w-[14rem] rounded-md border border-border bg-card px-2 py-1.5 text-[10px] shadow-xl"
      style={{
        left,
        top,
        transform: `translateX(${shift})`,
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
    </div>,
    document.body,
  );
}
