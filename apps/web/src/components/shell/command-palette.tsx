import { useNavigate } from "@tanstack/react-router";
import * as React from "react";
import { useMemo, useRef, useState } from "react";
import { ArrowRight, LayoutDashboard, Settings } from "lucide-react";
import { toolCatalog } from "@toolbox/contracts";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";

/** Ctrl/Cmd+K 命令面板：搜索并跳转工具与页面。 */
export function CommandPalette({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(0);
  const listRef = useRef<HTMLDivElement>(null);

  const items = useMemo(
    () => [
      {
        id: "dashboard",
        name: "仪表盘",
        desc: "概览与最近使用",
        to: "/dashboard",
        icon: LayoutDashboard,
      },
      { id: "settings", name: "设置", desc: "外观、数据源与账户", to: "/settings", icon: Settings },
      ...toolCatalog.map((tool) => ({
        id: tool.id,
        name: tool.name,
        desc: tool.description,
        to: "/tools/" + tool.id,
        icon: ArrowRight,
      })),
    ],
    [],
  );

  const filtered = items.filter((item) =>
    (item.name + " " + item.desc).toLowerCase().includes(query.trim().toLowerCase()),
  );

  /** 关闭时清空搜索词与选中项：放在这里而不是 effect 里，避免同步 setState 引发的连锁渲染。 */
  const handleOpenChange = (next: boolean) => {
    if (!next) {
      setQuery("");
      setSelected(0);
    }
    onOpenChange(next);
  };

  function go(item: (typeof items)[number]) {
    handleOpenChange(false);
    void navigate({ to: item.to });
  }

  /** 键盘导航：↓/↑ 移动，Enter 选中，Esc 交给 Dialog 关闭。 */
  function onKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (filtered.length === 0) return;

    if (event.key === "ArrowDown") {
      event.preventDefault();
      setSelected((index) => (index + 1) % filtered.length);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setSelected((index) => (index - 1 + filtered.length) % filtered.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      const item = filtered[selected];
      if (item) go(item);
    }
  }

  // 选中项变化时把对应项滚进可视区。
  // 必须放在 effect 里 —— 渲染期间访问 ref 会读到上一次的 DOM。
  const activeIndex = Math.min(selected, Math.max(filtered.length - 1, 0));
  React.useEffect(() => {
    const target = listRef.current?.querySelector<HTMLElement>(
      '[data-cmd-index="' + activeIndex + '"]',
    );
    target?.scrollIntoView({ block: "nearest" });
  }, [activeIndex]);

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-xl p-0">
        <DialogTitle className="sr-only">命令面板</DialogTitle>
        <DialogDescription className="sr-only">搜索工具或页面并跳转</DialogDescription>
        <div className="border-b border-border p-3">
          <input
            autoFocus
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setSelected(0);
            }}
            onKeyDown={onKeyDown}
            placeholder="搜索工具、页面…（↑↓ 选择，Enter 打开）"
            className="h-9 w-full rounded-md bg-transparent px-2 text-sm outline-none placeholder:text-muted-foreground"
          />
        </div>
        <div ref={listRef} className="max-h-80 overflow-y-auto p-2">
          {filtered.length === 0 ? (
            <div className="px-3 py-8 text-center text-sm text-muted-foreground">
              <p>没有匹配结果</p>
              <button
                type="button"
                onClick={() => { const first = items[0]; if (first) go(first); }}
                className="mt-2 text-xs text-primary underline-offset-2 hover:underline"
              >
                打开仪表盘
              </button>
            </div>
          ) : (
            filtered.map((item, index) => (
              <button
                key={item.id}
                type="button"
                data-cmd-index={index}
                onMouseEnter={() => setSelected(index)}
                onClick={() => go(item)}
                className={
                  "flex w-full items-center gap-3 rounded-md px-3 py-2 text-left transition-colors " +
                  (index === activeIndex
                    ? "bg-accent text-accent-foreground"
                    : "hover:bg-accent hover:text-accent-foreground")
                }
              >
                <item.icon className="h-4 w-4 text-muted-foreground" />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium">{item.name}</span>
                  <span className="block truncate text-xs text-muted-foreground">{item.desc}</span>
                </span>
                {index === activeIndex ? (
                  <kbd className="rounded border border-border bg-muted px-1 font-mono text-[10px]">
                    Enter
                  </kbd>
                ) : null}
              </button>
            ))
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}