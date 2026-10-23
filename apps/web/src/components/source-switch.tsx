import * as React from "react";
import { Cloud, Database, Plus, Settings2 } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { useDataSource } from "@/lib/data-source";
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

/**
 * 数据源切换。
 *
 * 页面本身不区分本地 / 云端，这里只负责「换一个数据源连接」：
 * 选中后清空登录态并退回登录页（本地数据源会自动进入）。
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
  const [adding, setAdding] = React.useState(false);
  const [name, setName] = React.useState("");
  const [url, setUrl] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);
  const addCloud = useDataSource((state) => state.addCloud);

  if (!canSwitchSource()) return null;

  async function pick(id: string) {
    await switchDataSource(id);
    // 切到新数据源后，旧源的 bootstrap 探测结果必须丢弃 ——
    // 否则登录页会先展示上一个数据源的 initialized/错误状态
    // （切到本地时端口可能刚就绪，占位地址的失败结果也会被缓存）。
    queryClient.removeQueries({ queryKey: ["bootstrap"] });
    setOpen(false);
    onChanged?.();
  }

  function submitAdd() {
    const trimmedName = name.trim();
    const trimmedUrl = url.trim();
    if (trimmedName.length === 0) return setError("请给这个数据源起个名字");
    // 只接受能解析出 host 的 http/https 地址（拒绝 ftp:、javascript:、相对路径等）
    if (!isValidHttpUrl(trimmedUrl)) {
      return setError("地址格式不正确，例如 http://192.168.1.10:3000");
    }

    const source = addCloud({ name: trimmedName, url: trimmedUrl });
    const existed = cloudSources.some((item) => item.url === source.url);
    setAdding(false);
    setName("");
    setUrl("");
    setError(null);
    if (existed) toast.info("这个地址已在列表中，已为你选中");
    void pick(source.id);
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
        title="切换数据源"
      >
        {type === "local" ? <Database className="h-3 w-3" /> : <Cloud className="h-3 w-3" />}
        {label}
        <Settings2 className="h-3 w-3 opacity-50" />
      </button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>切换数据源</DialogTitle>
            <DialogDescription>
              选中的服务器不同，数据也不同。切换后需要重新登录。
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <SourceRow
              active={activeId === "local"}
              icon={<Database className="h-4 w-4" />}
              name="本地数据"
              note="这台电脑 · 无需登录"
              onClick={() => void pick("local")}
            />
            {cloudSources.map((source) => (
              <SourceRow
                key={source.id}
                active={activeId === source.id}
                icon={<Cloud className="h-4 w-4" />}
                name={source.name}
                note={source.url}
                onClick={() => void pick(source.id)}
              />
            ))}
          </div>

          {adding ? (
            <div className="space-y-3 rounded-lg border border-border p-3">
              <Field>
                <FieldLabel htmlFor="src-name">名称</FieldLabel>
                <Input
                  id="src-name"
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                  placeholder="例如：公司服务器"
                  autoFocus
                />
              </Field>
              <Field>
                <FieldLabel htmlFor="src-url">服务器地址</FieldLabel>
                <Input
                  id="src-url"
                  value={url}
                  onChange={(event) => setUrl(event.target.value)}
                  placeholder="http://192.168.1.10:3000"
                  className="font-mono"
                />
                {error ? <FieldError>{error}</FieldError> : null}
              </Field>
              <div className="flex gap-2">
                <Button onClick={submitAdd}>添加并切换</Button>
                <Button
                  variant="outline"
                  onClick={() => {
                    setAdding(false);
                    setError(null);
                  }}
                >
                  取消
                </Button>
              </div>
            </div>
          ) : (
            <Button variant="outline" onClick={() => setAdding(true)}>
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
  onClick,
}: {
  active: boolean;
  icon: React.ReactNode;
  name: string;
  note: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-3 rounded-lg border px-3 py-2.5 text-left transition-colors",
        active
          ? "border-primary/40 bg-primary/5"
          : "border-border hover:bg-accent",
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
        <span className="block truncate text-sm font-medium">{name}</span>
        <span className="block truncate text-xs text-muted-foreground">{note}</span>
      </span>
      {active ? <span className="text-xs text-primary">使用中</span> : null}
    </button>
  );
}