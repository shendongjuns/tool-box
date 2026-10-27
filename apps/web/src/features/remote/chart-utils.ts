/**
 * 找到最接近鼠标 x 坐标的数据点索引。
 *
 * 数据按时间升序排列，最多 60 个点，线性换算即可（无需二分）。
 * 单独放一个文件是为了避免 chart-tooltip.tsx 同时导出组件和函数 ——
 * 那会破坏 Fast Refresh 的组件边界判断。
 */
export function nearestIndex(cursorX: number, innerWidth: number, count: number): number {
  if (count === 0) return -1;
  const ratio = Math.max(0, Math.min(1, cursorX / Math.max(1, innerWidth)));
  return Math.round(ratio * (count - 1));
}
