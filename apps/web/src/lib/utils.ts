import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** 合并 className，后者覆盖前者的 Tailwind 冲突项。 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

/** 相对时间：刚刚 / 5 分钟前 / 昨天 / 2026-10-20 */
export function relativeTime(timestamp: number): string {
  const delta = Date.now() - timestamp;
  const minute = 60_000;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (delta < minute) return "刚刚";
  if (delta < hour) return `${Math.floor(delta / minute)} 分钟前`;
  if (delta < day) return `${Math.floor(delta / hour)} 小时前`;
  if (delta < 2 * day) return "昨天";
  if (delta < 30 * day) return `${Math.floor(delta / day)} 天前`;
  return new Date(timestamp).toLocaleDateString("zh-CN");
}

export function formatDateTime(timestamp: number): string {
  return new Date(timestamp).toLocaleString("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}
