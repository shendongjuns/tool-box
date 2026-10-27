import * as React from "react";
import { Plus, Server as ServerIcon, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { Server } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { relativeTime } from "@/lib/utils";
import { probeServerLatency } from "@/lib/ssh";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ServerFormDialog } from "./server-form";

/** 服务器列表。 */
export function ServerList({
  activeId,
  onConnect,
}: {
  activeId: string | null;
  onConnect: (server: Server) => void;
}) {
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();
  const [editing, setEditing] = React.useState<Server | null>(null);
  const [creating, setCreating] = React.useState(false);
  /**
   * 表单实例计数器。
   *
   * 每次打开表单自增，作为 key 的一部分 —— 保证「编辑 A → 关闭 → 新建」
   * 这类操作一定拿到全新实例，避免残留上一次的输入。
   */
  const [formSeq, setFormSeq] = React.useState(0);

  const openCreate = React.useCallback(() => {
    setEditing(null);
    setCreating(true);
    setFormSeq((n) => n + 1);
  }, []);

  const openEdit = React.useCallback((server: Server) => {
    setCreating(false);
    setEditing(server);
    setFormSeq((n) => n + 1);
  }, []);

  const servers = useQuery({
    queryKey: queryKeys.servers(sourceKey),
    queryFn: () => api.listServers(),
  });

  const remove = useMutation({
    mutationFn: (id: string) => api.deleteServer(id),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: queryKeys.servers(sourceKey) });
      toast.success("已删除");
    },
    onError: (error: unknown) =>
      toast.error(error instanceof Error ? error.message : "删除失败"),
  });

  const items = React.useMemo(() => servers.data?.items ?? [], [servers.data]);

  // 延迟探测：进入列表后逐条测一次，可点击重测
  const [latency, setLatency] = React.useState<
    Record<string, { kind: "ok" | "timeout" | "error"; ms: number; loading?: boolean }>
  >({});

  const measure = React.useCallback(async (server: Server) => {
    setLatency((prev) => ({ ...prev, [server.id]: { kind: "ok", ms: 0, loading: true } }));
    const result = await probeServerLatency(server.host, server.port);
    setLatency((prev) => ({ ...prev, [server.id]: result }));
  }, []);

  React.useEffect(() => {
    if (items.length === 0) return;
    // 直接进列表时自动探测一次（不阻塞渲染）
    const timer = window.setTimeout(() => {
      void Promise.all(items.map((server) => measure(server)));
    }, 120);
    return () => window.clearTimeout(timer);
  }, [items, measure]);

  return (
    <div className="space-y-2">
      {servers.isLoading ? (
        <div className="space-y-2">
          {[0, 1].map((index) => (
            <Skeleton key={index} className="h-16 w-full" />
          ))}
        </div>
      ) : items.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
            <ServerIcon className="h-8 w-8 text-muted-foreground/40" />
            <div>
              <p className="text-sm font-medium">还没有服务器</p>
              <p className="mt-1 text-xs text-muted-foreground">
                添加一台服务器，即可使用 SSH 终端、SFTP 与系统监控
              </p>
            </div>
            <Button size="sm" onClick={() => openCreate()}>
              <Plus className="h-3.5 w-3.5" />
              添加服务器
            </Button>
          </CardContent>
        </Card>
      ) : (
        <>
          {items.map((server) => (
            <div
              key={server.id}
              className={
                "group flex items-center gap-3 rounded-lg border px-3 py-2.5 transition-colors " +
                (server.id === activeId
                  ? "border-primary/40 bg-primary/[0.04]"
                  : "border-border hover:bg-accent/40")
              }
            >
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-md bg-muted text-muted-foreground">
                <ServerIcon className="h-4 w-4" />
              </span>

              <button
                type="button"
                onClick={() => onConnect(server)}
                className="min-w-0 flex-1 text-left"
              >
                <span className="block truncate text-sm font-medium">{server.name}</span>
                <span className="mt-0.5 block truncate font-mono text-xs text-muted-foreground">
                  {server.username}@{server.host}:{server.port}
                  {server.lastConnectedAt
                    ? ` · ${relativeTime(server.lastConnectedAt)}`
                    : ""}
                </span>
              </button>

              <LatencyPill
                state={latency[server.id]}
                onRetry={() => void measure(server)}
              />

              <span className="flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                <Button size="sm" variant="ghost" onClick={() => openEdit(server)}>
                  编辑
                </Button>
                <button
                  type="button"
                  onClick={() => remove.mutate(server.id)}
                  title="删除"
                  className="rounded p-1.5 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </span>
            </div>
          ))}

          <Button size="sm" variant="ghost" className="w-full" onClick={() => openCreate()}>
            <Plus className="h-3.5 w-3.5" />
            添加服务器
          </Button>
        </>
      )}

      {/*
        key 要同时反映「新建/编辑」与「哪一条」。
        只用 editing?.id 的话，"编辑 A 后关掉再点新建" 仍是同一个 key，
        React 复用实例，表单里残留 A 的内容。
      */}
      <ServerFormDialog
        key={`form-${formSeq}`}
        open={creating || editing !== null}
        server={editing}
        onClose={() => {
          setCreating(false);
          setEditing(null);
        }}
      />
    </div>
  );
}
/** 延迟徽标：绿 = 正常，黄 = 较慢，红 = 不可达。 */
function LatencyPill({
  state,
  onRetry,
}: {
  state?: { kind: "ok" | "timeout" | "error"; ms: number; loading?: boolean };
  onRetry: () => void;
}) {
  if (!state) {
    return <span className="w-14 shrink-0 text-right text-[10px] text-muted-foreground/40">—</span>;
  }

  if (state.loading) {
    return (
      <span className="w-14 shrink-0 text-right text-[10px] text-muted-foreground/60">
        …
      </span>
    );
  }

  const tone =
    state.kind === "timeout" || state.kind === "error"
      ? "text-red-600 dark:text-red-400 border-red-500/30 bg-red-500/10"
      : state.ms < 80
        ? "text-emerald-600 dark:text-emerald-400 border-emerald-500/30 bg-emerald-500/10"
        : state.ms < 200
          ? "text-amber-600 dark:text-amber-400 border-amber-500/30 bg-amber-500/10"
          : "text-orange-600 dark:text-orange-400 border-orange-500/30 bg-orange-500/10";

  const label =
    state.kind === "timeout" ? "超时" : state.kind === "error" ? "不可达" : `${state.ms}ms`;

  return (
    <button
      type="button"
      onClick={onRetry}
      title="点击重新测量"
      className={`w-14 shrink-0 rounded-full border px-1.5 py-0.5 text-center text-[10px] font-medium tabular-nums transition-colors hover:brightness-110 ${tone}`}
    >
      {label}
    </button>
  );
}