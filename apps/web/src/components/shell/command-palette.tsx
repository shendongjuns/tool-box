import { useNavigate } from "@tanstack/react-router";
import { useState } from "react";
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

  const items = [
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
      to: `/tools/${tool.id}`,
      icon: ArrowRight,
    })),
  ];

  const filtered = items.filter((item) =>
    `${item.name} ${item.desc}`.toLowerCase().includes(query.trim().toLowerCase()),
  );

  /** 关闭时清空搜索词：放在这里而不是 effect 里，避免同步 setState 引发的连锁渲染。 */
  const handleOpenChange = (next: boolean) => {
    if (!next) setQuery("");
    onOpenChange(next);
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-xl p-0">
        <DialogTitle className="sr-only">命令面板</DialogTitle>
        <DialogDescription className="sr-only">搜索工具或页面并跳转</DialogDescription>
        <div className="border-b border-border p-3">
          <input
            autoFocus
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索工具、页面…"
            className="h-9 w-full rounded-md bg-transparent px-2 text-sm outline-none placeholder:text-muted-foreground"
          />
        </div>
        <div className="max-h-80 overflow-y-auto p-2">
          {filtered.length === 0 ? (
            <p className="px-3 py-8 text-center text-sm text-muted-foreground">没有匹配结果</p>
          ) : (
            filtered.map((item) => (
              <button
                key={item.id}
                type="button"
                onClick={() => {
                  handleOpenChange(false);
                  void navigate({ to: item.to });
                }}
                className="flex w-full items-center gap-3 rounded-md px-3 py-2 text-left transition-colors hover:bg-accent hover:text-accent-foreground"
              >
                <item.icon className="h-4 w-4 text-muted-foreground" />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium">{item.name}</span>
                  <span className="block truncate text-xs text-muted-foreground">{item.desc}</span>
                </span>
              </button>
            ))
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
