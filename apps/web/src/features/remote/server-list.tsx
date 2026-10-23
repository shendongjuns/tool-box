import * as React from "react";
import { Plus, Server as ServerIcon, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { Server } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { relativeTime } from "@/lib/utils";
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

  const items = servers.data?.items ?? [];

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
            <Button size="sm" onClick={() => setCreating(true)}>
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

              <span className="flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                <Button size="sm" variant="ghost" onClick={() => setEditing(server)}>
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

          <Button size="sm" variant="ghost" className="w-full" onClick={() => setCreating(true)}>
            <Plus className="h-3.5 w-3.5" />
            添加服务器
          </Button>
        </>
      )}

      <ServerFormDialog
        key={editing?.id ?? "new"}
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