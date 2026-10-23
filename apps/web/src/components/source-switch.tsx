import * as React from "react";
import { Cloud, Database, Pencil, Plus, Settings2, Trash2 } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { useDataSource, type CloudSource } from "@/lib/data-source";
import { switchDataSource } from "@/lib/session";
import { canSwitchSource } from "@/lib/source";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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
 * 数据源切换。
 *
 * 交互约定：
 * - **保存 ≠ 切换**：新增/编辑只写入列表，不会退出登录。
 * - **只有点「使用」才切换**：切换会清空登录态并回到登录页。
 *
 * 这样即使填错地址，也不会被直接踢出登录页。
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
    if (id === activeId) {
      setOpen(false);
      return;
    }
    setPendingId(id);
    await switchDataSource(id);
    // 切到新数据源后，旧源的 bootstrap 探测结果必须丢弃
    queryClient.removeQueries({ queryKey: ["bootstrap"] });
    setPendingId(null);
    setOpen(false);
    onChanged?.();
  }

  function startAdd() {
    setDraft({ id: null, name: "", url: "" });
    setError(null);
  }

  function startEdit(source: CloudSource) {
    setDraft({ id: source.id, name: source.name, url: source.url });
    setError(null);
  }

  /** 保存：只写列表，不切换。 */
  function save() {
    if (!draft) return;
    const name = draft.name.trim();
    const url = draft.url.trim();
    if (name.length === 0) return setError("请给这个数据源起个名字");
    if (!isValidHttpUrl(url)) {
      return setError("地址格式不正确，例如 http://192.168.1.10:3000");
    }

    if (draft.id) {
      updateCloud(draft.id, { name, url });
      toast.success("已保存，点「使用」即可切换");
    } else {
      const duplicate = cloudSources.find((item) => item.url === url.replace(/\/$/, ""));
      if (duplicate) {
        setError("这个地址已经在列表里了");
        return;
      }
      addCloud({ name, url });
      toast.success("已添加，点「使用」即可切换");
    }
    setDraft(null);
    setError(null);
  }

  function remove(source: CloudSource) {
    removeCloud(source.id);
    toast.success(`已移除 ${source.name}`);
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={cn(
          "inline-flex items-center gap-1.5 rounded-full border border-border px-2 py-0.5 text-[11px] font-medium transition-colors hover:bg-accent",
          type === "local"
            ? "text-emerald-600 dark:text-emerald-400"
            : "text-sky-600 dark:text-sky-400",
          compact && "text-xs px-2.5 py-1",
        )}
        title="管理数据源"
      >
        {type === "local" ? <Database className="h-3 w-3" /> : <Cloud className="h-3 w-3" />}
        {label}
        <Settings2 className="h-3 w-3 opacity-50" />
      </button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>数据源</DialogTitle>
            <DialogDescription>
              点「使用」才会切换并重新登录；新增或修改只是保存，不会退出当前账号。
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <SourceRow
              active={activeId === "local"}
              icon={<Database className="h-4 w-4" />}
              name="本地数据"
              note="这台电脑"
              busy={pendingId === "local"}
              onClick={() => void pick("local")}
            />
            {cloudSources.map((source) => (
              <SourceRow
                key={source.id}
                active={activeId === source.id}
                icon={<Cloud className="h-4 w-4" />}
                name={source.name}
                note={source.url}
                busy={pendingId === source.id}
                onClick={() => void pick(source.id)}
                onEdit={() => startEdit(source)}
                onRemove={() => remove(source)}
              />
            ))}
          </div>

          {draft ? (
            <div className="space-y-3 rounded-lg border border-border p-3">
              <Field>
                <FieldLabel htmlFor="src-name">名称</FieldLabel>
                <Input
                  id="src-name"
                  value={draft.name}
                  onChange={(event) => setDraft({ ...draft, name: event.target.value })}
                  placeholder="例如：公司服务器"
                  autoFocus
                />
              </Field>
              <Field>
                <FieldLabel htmlFor="src-url">服务器地址</FieldLabel>
                <Input
                  id="src-url"
                  value={draft.url}
                  onChange={(event) => setDraft({ ...draft, url: event.target.value })}
                  placeholder="http://192.168.1.10:3000"
                  className="font-mono"
                />
                {error ? (
                  <FieldError>{error}</FieldError>
                ) : (
                  <p className="text-xs text-muted-foreground">
                    保存后不会自动切换，需要点「使用」。
                  </p>
                )}
              </Field>
              <div className="flex gap-2">
                <Button onClick={save}>保存</Button>
                <Button
                  variant="outline"
                  onClick={() => {
                    setDraft(null);
                    setError(null);
                  }}
                >
                  取消
                </Button>
              </div>
            </div>
          ) : (
            <Button variant="outline" onClick={startAdd}>
              <Plus className="h-4 w-4" />
              添加云端服务器
            </Button>
          )}

          <DialogFooter>
            <Button variant="ghost" onClick={() => setOpen(false)}>
              关闭
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function SourceRow({
  active,
  icon,
  name,
  note,
  latencyUrl,
  busy,
  onClick,
  onEdit,
  onRemove,
}: {
  active: boolean;
  icon: React.ReactNode;
  name: string;
  note: string;
  latencyUrl?: string;
  busy?: boolean;
  onClick: () => void;
  onEdit?: () => void;
  onRemove?: () => void;
}) {
  return (
    <div
      className={cn(
        "flex items-center gap-3 rounded-lg border px-3 py-2.5 transition-colors",
        active ? "border-primary/40 bg-primary/5" : "border-border",
      )}
    >
      <span
        className={cn(
          "grid h-8 w-8 shrink-0 place-items-center rounded-lg",
          active ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground",
        )}
      >
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-1.5">
          <span className="truncate text-sm font-medium">{name}</span>
          {latencyUrl ? <LatencyBadge url={latencyUrl} /> : null}
        </span>
        <span className="block truncate text-xs text-muted-foreground">{note}</span>
      </span>

      {onEdit ? (
        <button
          type="button"
          onClick={onEdit}
          title="编辑"
          className="rounded p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
        >
          <Pencil className="h-3.5 w-3.5" />
        </button>
      ) : null}
      {onRemove ? (
        <button
          type="button"
          onClick={onRemove}
          title="移除"
          className="rounded p-1 text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      ) : null}

      {active ? (
        <span className="shrink-0 text-xs text-primary">使用中</span>
      ) : (
        <Button size="sm" variant="outline" onClick={onClick} disabled={busy}>
          {busy ? "切换中…" : "使用"}
        </Button>
      )}
    </div>
  );
}