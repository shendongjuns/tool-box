import * as React from "react";
import { Link, useRouterState } from "@tanstack/react-router";
import {
  Binary,
  Braces,
  ChevronLeft,
  Clock,
  Fingerprint,
  Hash,
  LayoutDashboard,
  Link2,
  PanelLeftClose,
  PanelLeftOpen,
  Settings,
} from "lucide-react";
import { toolCatalog } from "@toolbox/contracts";
import { cn } from "@/lib/utils";
import { SourceBadge } from "./source-badge";
import { BrandLogo } from "@/components/brand-logo";
import { UserAvatar } from "@/components/user-avatar";
import { useDataSource } from "@/lib/data-source";
import { useAuth } from "@/lib/auth-session";

const icons: Record<string, React.ComponentType<{ className?: string }>> = {
  Braces,
  Binary,
  Link: Link2,
  Clock,
  Hash,
  Fingerprint,
};

const categoryLabels: Record<string, string> = {
  work: "工作",
  data: "数据处理",
  database: "数据库",
  text: "文本",
  encode: "编解码",
  system: "系统",
  other: "其他",
};

export function Sidebar({
  collapsed,
  onToggle,
  onTogglePersist,
}: {
  collapsed: boolean;
  onToggle: () => void;
  /** 把折叠状态写回服务端设置；未提供时只切换本地状态 */
  onTogglePersist?: (next: boolean) => void;
}) {
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const user = useAuth((state) => state.auth?.user);
  const sourceLabel = useDataSource((state) => state.label);
  const sourceType = useDataSource((state) => state.type);

  const toggle = React.useCallback(() => {
    const next = !collapsed;
    onToggle();
    onTogglePersist?.(next);
  }, [collapsed, onToggle, onTogglePersist]);

  const groups = React.useMemo(() => {
    const map = new Map<string, (typeof toolCatalog)[number][]>();
    for (const tool of toolCatalog) {
      const bucket = map.get(tool.category) ?? [];
      bucket.push(tool);
      map.set(tool.category, bucket);
    }
    return [...map.entries()];
  }, []);

  return (
    <aside
      className={cn(
        "relative flex shrink-0 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground transition-[width] duration-200",
        collapsed ? "w-16" : "w-60",
      )}
    >
      <div
        className={cn(
          "flex h-12 items-center px-3",
          collapsed ? "justify-center" : "justify-start",
        )}
      >
        {collapsed ? (
          // 收起时只剩一个极简的 "TB" 字标，保持品牌识别
          <span className="brand-wordmark select-none text-base font-extrabold italic leading-none">
            TB
          </span>
        ) : (
          <div className="flex min-w-0 items-center gap-2">
            <BrandLogo size="md" />
            <span className="rounded-full border border-border/70 px-1.5 py-px text-[10px] font-medium text-muted-foreground">
              2.0.0
            </span>
          </div>
        )}
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto px-2 pb-3">
        <SidebarLink
          to="/dashboard"
          active={pathname === "/dashboard"}
          collapsed={collapsed}
          icon={<LayoutDashboard className="h-4 w-4" />}
          label="仪表盘"
        />

        {groups.map(([category, tools]) => (
          <div key={category} className="pt-2">
            {!collapsed && (
              <p className="px-2 pb-1 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                {categoryLabels[category] ?? category}
              </p>
            )}
            {tools.map((tool) => {
              const Icon = icons[tool.icon] ?? Braces;
              return (
                <SidebarLink
                  key={tool.id}
                  to="/tools/$toolId"
                  params={{ toolId: tool.id }}
                  active={pathname === `/tools/${tool.id}`}
                  collapsed={collapsed}
                  icon={<Icon className="h-4 w-4" />}
                  label={tool.name}
                  title={tool.description}
                />
              );
            })}
          </div>
        ))}
      </nav>

      <div className="space-y-1 border-t border-sidebar-border p-2">
        <SidebarLink
          to="/settings"
          active={pathname.startsWith("/settings")}
          collapsed={collapsed}
          icon={<Settings className="h-4 w-4" />}
          label="设置"
        />
        <button
          type="button"
          onClick={toggle}
          className={cn(
            "flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-foreground",
            collapsed && "justify-center",
          )}
          title={collapsed ? "展开侧栏" : "收起侧栏"}
        >
          {collapsed ? (
            <PanelLeftOpen className="h-4 w-4" />
          ) : (
            <>
              <PanelLeftClose className="h-4 w-4" />
              <span>收起侧栏</span>
            </>
          )}
        </button>
      </div>

      {!collapsed && (
        <div className="flex items-center gap-2 border-t border-sidebar-border px-3 py-2.5">
          <UserAvatar size={28} />
          <div className="min-w-0 flex-1">
            <p className="truncate text-xs font-medium">
              {user?.displayName ?? user?.username ?? "未登录"}
            </p>
            <p className="truncate text-[11px] text-muted-foreground">{sourceLabel}</p>
          </div>
          <SourceBadge />
        </div>
      )}

      {/* 收起态：用颜色点提示当前数据源类型（悬停显示完整名称） */}
      {collapsed && (
        <div
          className="flex justify-center border-t border-sidebar-border py-2.5"
          title={sourceLabel}
        >
          <span
            className={cn(
              "h-2 w-2 rounded-full",
              sourceType === "local" ? "bg-emerald-500" : "bg-sky-500",
            )}
          />
        </div>
      )}
    </aside>
  );
}

function SidebarLink({
  to,
  params,
  active,
  collapsed,
  icon,
  label,
  title,
}: {
  to: string;
  params?: Record<string, string>;
  active: boolean;
  collapsed: boolean;
  icon: React.ReactNode;
  label: string;
  title?: string;
}) {
  return (
    <Link
      to={to}
      params={params}
      title={title ?? label}
      className={cn(
        "flex items-center gap-2.5 rounded-md px-2 py-1.5 text-sm transition-colors",
        active
          ? "bg-sidebar-accent font-medium text-foreground"
          : "text-muted-foreground hover:bg-sidebar-accent/70 hover:text-foreground",
        collapsed && "justify-center px-0",
      )}
    >
      <span className={cn(active && "text-primary")}>{icon}</span>
      {!collapsed && <span className="truncate">{label}</span>}
      {active && !collapsed && <ChevronLeft className="ml-auto h-3 w-3 rotate-180 text-primary" />}
    </Link>
  );
}