import { createFileRoute, Link } from "@tanstack/react-router";
import { Activity, ArrowUpRight, Boxes, Clock3, HardDrive, Pin, WifiOff } from "lucide-react";
import { toolCatalog } from "@toolbox/contracts";
import { useDashboardQuery } from "@/lib/hooks";
import { useAuth } from "@/lib/auth-session";
import { useDataSource } from "@/lib/data-source";
import { DATA_SOURCES } from "@/lib/source";
import { relativeTime } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { SourceSwitch } from "@/components/source-switch";

export const Route = createFileRoute("/_app/dashboard")({
  component: DashboardPage,
});

function DashboardPage() {
  const user = useAuth((state) => state.auth?.user);
  const source = useDataSource((state) => state.source);
  const dashboard = useDashboardQuery();

  const hour = new Date().getHours();
  const greeting = hour < 6 ? "夜深了" : hour < 12 ? "早上好" : hour < 18 ? "下午好" : "晚上好";
  const stats = dashboard.data?.stats;

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm text-muted-foreground">
            {greeting}，{user?.displayName ?? user?.username}
          </p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">仪表盘</h1>
        </div>
        <div className="flex items-center gap-3">
          <Badge variant={source === "local" ? "success" : "default"}>
            {DATA_SOURCES[source].label}
          </Badge>
          <SourceSwitch />
        </div>
      </header>

      {dashboard.isError ? (
        <div className="flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
          <WifiOff className="h-4 w-4 shrink-0" />
          {dashboard.error instanceof Error ? dashboard.error.message : "加载失败"}
        </div>
      ) : null}

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label="可用工具"
          value={stats?.totalTools ?? toolCatalog.length}
          icon={<Boxes className="h-4 w-4" />}
          hint={`共 ${toolCatalog.length} 个内置工具`}
          loading={dashboard.isLoading}
        />
        <StatCard
          label="置顶工具"
          value={stats?.pinnedTools ?? 0}
          icon={<Pin className="h-4 w-4" />}
          hint="在工具页可置顶常用项"
          loading={dashboard.isLoading}
        />
        <StatCard
          label="活跃会话"
          value={stats?.activeSessions}
          icon={<Activity className="h-4 w-4" />}
          hint="30 天内有效并自动续期"
          loading={dashboard.isLoading}
        />
        <StatCard
          label="数据源"
          value={source === "local" ? "本地" : "云端"}
          icon={<HardDrive className="h-4 w-4" />}
          hint={DATA_SOURCES[source].description}
          loading={false}
        />
      </section>

      <section className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle>最近使用</CardTitle>
            <Clock3 className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent className="space-y-1">
            {dashboard.isLoading ? (
              <div className="space-y-2">
                {[0, 1, 2].map((index) => (
                  <Skeleton key={index} className="h-12 w-full" />
                ))}
              </div>
            ) : dashboard.data?.recentTools.length ? (
              dashboard.data.recentTools.map((tool) => (
                <Link
                  key={tool.id}
                  to="/tools/$toolId"
                  params={{ toolId: tool.id }}
                  className="flex items-center gap-3 rounded-lg px-2 py-2.5 transition-colors hover:bg-accent"
                >
                  <div className="grid h-9 w-9 place-items-center rounded-lg border border-border bg-card text-sm font-semibold text-primary">
                    {tool.name.slice(0, 1)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{tool.name}</p>
                    <p className="truncate text-xs text-muted-foreground">{tool.description}</p>
                  </div>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {tool.lastOpenedAt ? relativeTime(tool.lastOpenedAt) : "尚未打开"}
                  </span>
                  <ArrowUpRight className="h-4 w-4 shrink-0 text-muted-foreground" />
                </Link>
              ))
            ) : (
              <p className="py-6 text-center text-sm text-muted-foreground">
                还没有使用记录，从左侧挑一个工具开始吧。
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>服务状态</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <Row label="版本" value={dashboard.data?.server.version ?? "—"} />
            <Row
              label="运行时长"
              value={
                dashboard.data ? `${Math.floor(dashboard.data.server.uptime / 60)} 分钟` : "—"
              }
            />
            <Row
              label="最近活动"
              value={
                dashboard.data?.lastActiveAt ? relativeTime(dashboard.data.lastActiveAt) : "暂无"
              }
            />
            <Row label="数据源" value={DATA_SOURCES[source].label} />
          </CardContent>
        </Card>
      </section>
    </div>
  );
}

function StatCard({
  label,
  value,
  icon,
  hint,
  loading,
}: {
  label: string;
  value?: number | string;
  icon: React.ReactNode;
  hint?: string;
  loading: boolean;
}) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between text-muted-foreground">
          <span className="text-xs font-medium">{label}</span>
          {icon}
        </div>
        <div className="mt-2 h-7 text-2xl font-semibold tracking-tight">
          {loading ? <Skeleton className="h-7 w-12" /> : (value ?? "—")}
        </div>
        {hint ? <p className="mt-1 line-clamp-1 text-[11px] text-muted-foreground">{hint}</p> : null}
      </CardContent>
    </Card>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="truncate font-medium">{value}</span>
    </div>
  );
}