import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * 轻量右键菜单。
 *
 * 没有引入 Radix 的 ContextMenu（体积与依赖不值），
 * 这里用 fixed 定位 + 点击外部关闭实现，够用且可控。
 */
export interface MenuItem {
  label: string;
  icon?: React.ComponentType<{ className?: string }>;
  onSelect: () => void;
  destructive?: boolean;
}

export function ContextMenu({
  x,
  y,
  items,
  onClose,
}: {
  x: number;
  y: number;
  items: MenuItem[];
  onClose: () => void;
}) {
  const ref = React.useRef<HTMLDivElement>(null);
  const [position, setPosition] = React.useState({ x, y });

  // 贴着视口边缘时向内收，避免被裁掉
  React.useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const rect = element.getBoundingClientRect();
    const nextX = Math.min(x, window.innerWidth - rect.width - 8);
    const nextY = Math.min(y, window.innerHeight - rect.height - 8);
    setPosition({ x: Math.max(8, nextX), y: Math.max(8, nextY) });
  }, [x, y]);

  React.useEffect(() => {
    const handlePointer = (event: MouseEvent) => {
      if (ref.current && !ref.current.contains(event.target as Node)) onClose();
    };
    const handleKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    // 捕获阶段监听，避免被内部 stopPropagation 拦掉
    document.addEventListener("mousedown", handlePointer, true);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("mousedown", handlePointer, true);
      document.removeEventListener("keydown", handleKey);
    };
  }, [onClose]);

  return (
    <div
      ref={ref}
      role="menu"
      style={{ left: position.x, top: position.y }}
      className="fixed z-50 min-w-[9rem] overflow-hidden rounded-lg border border-border bg-card p-1 shadow-lg"
    >
      {items.map((item) => {
        const Icon = item.icon;
        return (
          <button
            key={item.label}
            type="button"
            role="menuitem"
            onClick={() => {
              onClose();
              item.onSelect();
            }}
            className={cn(
              "flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-xs transition-colors",
              item.destructive
                ? "text-destructive hover:bg-destructive/10"
                : "text-foreground hover:bg-accent",
            )}
          >
            {Icon ? <Icon className="h-3.5 w-3.5" /> : null}
            {item.label}
          </button>
        );
      })}
    </div>
  );
}
