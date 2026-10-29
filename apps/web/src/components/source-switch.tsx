import * as React from "react";
import { Check, Cloud, Database, Pencil, Plus, Settings2, Trash2 } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { useDataSource } from "@/lib/data-source";
import { reloadsOnSwitch, switchDataSource } from "@/lib/session";
import { canSwitchSource } from "@/lib/source";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { LatencyBadge } from "@/components/latency-badge";

/** 校验是否是可用的 http/https 地址。 */
function isValidHttpUrl(value: string): boolean {
  try {
    const parsed = new URL(value);
    return (
      (parsed.protocol === "http:" || parsed.protocol === "https:") && parsed.hostname.length > 0
    );
  } catch {
    return false;
  }
}

type Draft = { id: string | null; name: string; url: string };

/**
 * 数据源面板。
 *
 * 交互：保存只写列表，「使用」才切换（切换会重载/跳转登录页）。
 */
export function SourceSwitch({
  compact = false,
  onChanged,
}: {
  compact?: boolean;
  onChanged?: () => void;
}) {
  const { activeId, cloudSources, type, label } = useDataSource();
  const queryClient = useQueryClient();
  const [open, setOpen] = React.useState(false);
  const [draft, setDraft] = React.useState<Draft | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [pendingId, setPendingId] = React.useState<string | null>(null);

  const addCloud = useDataSource((state) => state.addCloud);
  const updateCloud = useDataSource((state) => state.updateCloud);
  const removeCloud = useDataSource((state) => state.removeCloud);

  if (!canSwitchSource()) return null;

  async function pick(id: string) {
    if (id === activeId) return setOpen(false);
    setPendingId(id);
    await switchDataSource(id);
    if (reloadsOnSwitch()) return;
    queryClient.removeQueries({ queryKey: ["bootstrap"] });
    setPendingId(null);
    setOpen(false);
    onChanged?.();
  }

  function save() {
    if (!draft) return;
    const name = draft.name.trim();
    const url = draft.url.trim();
    if (!name) return setError("请填写名称");
    if (!isValidHttpUrl(url)) return setError("地址格式不正确");

    if (draft.id) {
      updateCloud(draft.id, { name, url });
      toast.success("已保存");
    } else {
      if (cloudSources.some((item) => item.url === url.replace(/\/$/, ""))) {
        return setError("该地址已存在");
      }
      addCloud({ name, url });
      toast.success("已添加");
    }
    setDraft(null);
    setError(null);
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={cn(
          "inline-flex h-7 items-center gap-1.5 rounded-md border border-border px-2 text-xs font-medium transition-colors hover:bg-accent",
          type === "local"
            ? "text-emerald-600 dark:text-emerald-400"
            : "text-sky-600 dark:text-sky-400",
          compact && "h-8 px-2.5",
        )}
        title="数据源"
      >
        {type === "local" ? <Database className="h-3 w-3" /> : <Cloud className="h-3 w-3" />}
        <span className="max-w-[8rem] truncate">{label}</span>
        <Settings2 className="h-3 w-3 opacity-40" />
      </button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md gap-0 p-0">
          <DialogHeader className="border-b border-border px-4 py-3">
            <DialogTitle className="text-base">数据源</DialogTitle>
          </DialogHeader>

          <div className="max-h-[60vh] overflow-y-auto">
            <SourceItem
              active={activeId === "local"}
              icon={Database}
              name="本地数据"
              note="这台电脑"
              busy={pendingId === "local"}
              onPick={() => void pick("local")}
            />

            {cloudSources.map((source) => (
              <SourceItem
                key={source.id}
                active={activeId === source.id}
                icon={Cloud}
                name={source.name}
                note={source.url}
                latencyUrl={source.url}
                busy={pendingId === source.id}
                onPick={() => void pick(source.id)}
                onEdit={() => {
                  setDraft({ id: source.id, name: source.name, url: source.url });
                  setError(null);
                }}
                onRemove={
                  source.id === activeId
                    ? undefined
                    : () => {
                        removeCloud(source.id);
                        toast.success("已移除");
                      }
                }
              />
            ))}
          </div>

          {draft ? (
            <div className="space-y-3 border-t border-border p-4">
              <div className="grid gap-3 sm:grid-cols-2">
                <Field>
                  <FieldLabel htmlFor="src-name">名称</FieldLabel>
                  <Input
                    id="src-name"
                    value={draft.name}
                    onChange={(event) => setDraft({ ...draft, name: event.target.value })}
                    placeholder="公司服务器"
                    autoFocus
                  />
                </Field>
                <Field>
                  <FieldLabel htmlFor="src-url">地址</FieldLabel>
                  <Input
                    id="src-url"
                    value={draft.url}
                    onChange={(event) => setDraft({ ...draft, url: event.target.value })}
                    placeholder="http://10.0.0.2:7788"
                    className="font-mono text-xs"
                  />
                </Field>
              </div>
              {error ? <FieldError>{error}</FieldError> : null}
              <div className="flex justify-end gap-2">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    setDraft(null);
                    setError(null);
                  }}
                >
                  取消
                </Button>
                <Button size="sm" onClick={save}>
                  保存
                </Button>
              </div>
            </div>
          ) : (
            <div className="border-t border-border p-3">
              <Button
                size="sm"
                variant="ghost"
                className="w-full justify-start text-muted-foreground"
                onClick={() => {
                  setDraft({ id: null, name: "", url: "" });
                  setError(null);
                }}
              >
                <Plus className="h-3.5 w-3.5" />
                添加云端服务器
              </Button>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}

/** 单条数据源。整行可点；右侧只放必要操作。 */
function SourceItem({
  active,
  icon: Icon,
  name,
  note,
  latencyUrl,
  busy,
  onPick,
  onEdit,
  onRemove,
}: {
  active: boolean;
  icon: React.ComponentType<{ className?: string }>;
  name: string;
  note: string;
  latencyUrl?: string;
  busy?: boolean;
  onPick: () => void;
  onEdit?: () => void;
  onRemove?: () => void;
}) {
  return (
    <div
      className={cn(
        "group flex items-center gap-3 border-b border-border/60 px-4 py-2.5 last:border-b-0",
        active && "bg-primary/[0.04]",
      )}
    >
      <span
        className={cn(
          "grid h-8 w-8 shrink-0 place-items-center rounded-md",
          active ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground",
        )}
      >
        <Icon className="h-4 w-4" />
      </span>

      <button
        type="button"
        onClick={onPick}
        disabled={active || busy}
        className="min-w-0 flex-1 text-left disabled:cursor-default"
      >
        <span className="flex items-center gap-1.5">
          <span className="truncate text-sm font-medium">{name}</span>
          {latencyUrl ? <LatencyBadge url={latencyUrl} /> : null}
        </span>
        <span className="mt-0.5 block truncate text-xs text-muted-foreground">{note}</span>
      </button>

      {active ? (
        <span className="flex shrink-0 items-center gap-1 text-xs font-medium text-primary">
          <Check className="h-3.5 w-3.5" />
          当前
        </span>
      ) : busy ? (
        <span className="shrink-0 text-xs text-muted-foreground">切换中…</span>
      ) : (
        <span className="flex shrink-0 items-center opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
          {onEdit ? (
            <button
              type="button"
              onClick={onEdit}
              title="编辑"
              className="rounded p-1.5 text-muted-foreground hover:bg-accent hover:text-foreground"
            >
              <Pencil className="h-3.5 w-3.5" />
            </button>
          ) : null}
          {onRemove ? (
            <button
              type="button"
              onClick={onRemove}
              title="移除"
              className="rounded p-1.5 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
            >
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          ) : null}
        </span>
      )}
    </div>
  );
}
