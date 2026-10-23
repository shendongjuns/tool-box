import * as React from "react";
import { Link, useRouterState } from "@tanstack/react-router";
import {
  Binary,
  Braces,
  ChevronLeft,
  ChevronRight,
  Clock,
  Fingerprint,
  Hash,
  LayoutDashboard,
  Link2,
  PanelLeftClose,
  PanelLeftOpen,
  Server,
  Settings,
} from "lucide-react";
import { toolCatalog, toolCategoryMeta, toolGroupMeta, type ToolGroup } from "@toolbox/contracts";
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
  Server,
};

/** 按「分组 → 分类 → 工具」三层整理目录。 */
function buildTree() {
  const groupMap = new Map<
    ToolGroup,
    Map<string, (typeof toolCatalog)[number][]>
  >();

  for (const tool of toolCatalog) {
    const categories = groupMap.get(tool.group) ?? new Map();
    const bucket = categories.get(tool.category) ?? [];
    bucket.push(tool);
    categories.set(tool.category, bucket);
    groupMap.set(tool.group, categories);
  }

  return [...groupMap.entries()]
    .sort((a, b) => toolGroupMeta[a[0]].order - toolGroupMeta[b[0]].order)
    .map(([group, categories]) => ({
      group,
      label: toolGroupMeta[group].label,
      categories: [...categories.entries()]
        .sort((a, b) => {
          const ka = toolCategoryMeta[a[0] as keyof typeof toolCategoryMeta]?.order ?? 99;
          const kb = toolCategoryMeta[b[0] as keyof typeof toolCategoryMeta]?.order ?? 99;
          return ka - kb;
        })
        .map(([category, tools]) => ({
          category,
          label:
            toolCategoryMeta[category as keyof typeof toolCategoryMeta]?.label ?? category,
          tools: [...tools].sort((a, b) => a.defaultSortOrder - b.defaultSortOrder),
        })),
    }));
}

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

  const tree = React.useMemo(() => buildTree(), []);

  /*
   * 折叠状态存「被用户收起的集合」，默认全部展开。
   *
   * 当前路由所在的分组/分类总是展开（渲染时判断，不写 state），
   * 避免用户从深层页面回来时路径被折叠。
   */
  const currentToolId = pathname.startsWith("/tools/")
    ? pathname.replace("/tools/", "")
    : null;
  const current = currentToolId ? toolCatalog.find((tool) => tool.id === currentToolId) : null;

  const [closedGroups, setClosedGroups] = React.useState<Set<string>>(() => new Set());
  const [closedCategories, setClosedCategories] = React.useState<Set<string>>(() => new Set());

  const isGroupOpen = (group: string) =>
    !closedGroups.has(group) || current?.group === group;
  const isCategoryOpen = (category: string) =>
    !closedCategories.has(category) || current?.category === category;

  const toggleGroup = (group: string) =>
    setClosedGroups((prev) => {
      const next = new Set(prev);
      if (next.has(group)) next.delete(group);
      else next.add(group);
      return next;
    });

  const toggleCategory = (category: string) =>
    setClosedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(category)) next.delete(category);
      else next.add(category);
      return next;
    });

  const toggle = React.useCallback(() => {
    const next = !collapsed;
    onToggle();
    onTogglePersist?.(next);
  }, [collapsed, onToggle, onTogglePersist]);

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

      <nav className="flex-1 space-y-0.5 overflow-y-auto px-2 pb-3">
        <SidebarLink
          to="/dashboard"
          active={pathname === "/dashboard"}
          collapsed={collapsed}
          icon={<LayoutDashboard className="h-4 w-4" />}
          label="仪表盘"
        />

        {tree.map((group) => {
          const groupOpen = collapsed || isGroupOpen(group.group);
          return (
            <div key={group.group} className="pt-2">
              {/* 一级目录：分组 */}
              {collapsed ? (
                <p className="px-2 pb-1 text-[10px] font-medium uppercase tracking-wide text-muted-foreground/70">
                  {group.label.slice(0, 1)}
                </p>
              ) : (
                <button
                  type="button"
                  onClick={() => toggleGroup(group.group)}
                  className="flex w-full items-center gap-1 rounded-md px-2 py-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground transition-colors hover:text-foreground"
                >
                  {groupOpen ? (
                    <ChevronRight className="h-3 w-3 rotate-90" />
                  ) : (
                    <ChevronRight className="h-3 w-3" />
                  )}
                  {group.label}
                </button>
              )}

              {groupOpen &&
                group.categories.map((category) => {
                  const categoryOpen = collapsed || isCategoryOpen(category.category);
                  return (
                    <div key={category.category} className="mt-0.5">
                      {/* 二级目录：分类 */}
                      {!collapsed && (
                        <button
                          type="button"
                          onClick={() => toggleCategory(category.category)}
                          className="flex w-full items-center gap-1 rounded-md py-1 pl-6 pr-2 text-xs text-muted-foreground transition-colors hover:text-foreground"
                        >
                          {categoryOpen ? (
                            <ChevronRight className="h-3 w-3 rotate-90 opacity-60" />
                          ) : (
                            <ChevronRight className="h-3 w-3 opacity-60" />
                          )}
                          {category.label}
                        </button>
                      )}

                      {categoryOpen &&
                        category.tools.map((tool) => {
                          const Icon = icons[tool.icon] ?? Braces;
                          return (
                            <SidebarLink
                              key={tool.id}
                              to="/tools/$toolId"
                              params={{ toolId: tool.id }}
                              active={pathname === `/tools/${tool.id}`}
                              collapsed={collapsed}
                              indent={!collapsed}
                              icon={<Icon className="h-4 w-4" />}
                              label={tool.name}
                              title={tool.description}
                            />
                          );
                        })}
                    </div>
                  );
                })}
            </div>
          );
        })}
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
  indent = false,
  icon,
  label,
  title,
}: {
  to: string;
  params?: Record<string, string>;
  active: boolean;
  collapsed: boolean;
  indent?: boolean;
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
        "flex items-center gap-2.5 rounded-md py-1.5 pr-2 text-sm transition-colors",
        indent ? "pl-10" : "pl-2",
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