import * as React from "react";
import {
  ArrowUp,
  Download,
  File,
  Folder,
  FolderPlus,
  Pencil,
  RefreshCw,
  Trash2,
  Upload,
} from "lucide-react";
import { toast } from "sonner";
import {
  base64ToBlob,
  readLocalFileAsBase64,
  sftpList,
  sftpMkdir,
  sftpRead,
  sftpRemove,
  sftpRename,
  sftpWrite,
  type SftpEntry,
} from "@/lib/ssh";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let value = bytes / 1024;
  let index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  return `${value.toFixed(1)} ${units[index]}`;
}

function formatTime(seconds: number): string {
  if (!seconds) return "—";
  const date = new Date(seconds * 1000);
  return date.toLocaleString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** SFTP 文件浏览器。 */
export function SftpPanel({ sessionId }: { sessionId: string }) {
  const [path, setPath] = React.useState(".");
  const [entries, setEntries] = React.useState<SftpEntry[] | null>(null);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [creating, setCreating] = React.useState(false);
  const [newDir, setNewDir] = React.useState("");
  const [renaming, setRenaming] = React.useState<{ path: string; name: string } | null>(null);
  const fileInputRef = React.useRef<HTMLInputElement>(null);

  /*
   * 加载目录。
   *
   * 用 useCallback 包一层，effect 里只调用它 —— 真正的 setState 都发生在
   * await 之后（异步），不会触发「effect 内同步 setState」告警。
   */
  const load = React.useCallback(
    async (target: string) => {
      try {
        const list = await sftpList(sessionId, target);
        setEntries(list);
        setError(null);
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
        setEntries([]);
      } finally {
        setLoading(false);
      }
    },
    [sessionId],
  );

  React.useEffect(() => {
    // 首帧先标记 loading，再发起请求
    const timer = window.setTimeout(() => {
      setLoading(true);
      void load(".");
    }, 0);
    return () => window.clearTimeout(timer);
  }, [sessionId, load]);

  function parentPath(current: string): string {
    const trimmed = current.replace(/\/$/, "");
    const index = trimmed.lastIndexOf("/");
    if (index <= 0) return ".";
    return trimmed.slice(0, index);
  }

  async function handleDelete(entry: SftpEntry) {
    try {
      await sftpRemove(sessionId, entry.path, entry.isDir);
      toast.success(`已删除 ${entry.name}`);
      await load(path);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "删除失败");
    }
  }

  async function handleRename() {
    if (!renaming) return;
    const target = renaming.path.replace(/[^/]+$/, renaming.name);
    try {
      await sftpRename(sessionId, renaming.path, target);
      toast.success("已重命名");
      setRenaming(null);
      await load(path);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "重命名失败");
    }
  }

  async function handleMkdir() {
    if (!newDir.trim()) return;
    const target = path === "." ? newDir.trim() : `${path}/${newDir.trim()}`;
    try {
      await sftpMkdir(sessionId, target);
      toast.success("已创建目录");
      setNewDir("");
      setCreating(false);
      await load(path);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "创建失败");
    }
  }

  async function handleDownload(entry: SftpEntry) {
    try {
      const base64 = await sftpRead(sessionId, entry.path);
      const blob = base64ToBlob(base64);
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = entry.name;
      anchor.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "下载失败");
    }
  }

  async function handleUpload(file: File) {
    try {
      const base64 = await readLocalFileAsBase64(file);
      const target = path === "." ? file.name : `${path}/${file.name}`;
      await sftpWrite(sessionId, target, base64);
      toast.success(`已上传 ${file.name}`);
      await load(path);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "上传失败");
    }
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2">
      {/* 工具栏 */}
      <div className="flex flex-wrap items-center gap-1.5">
        <Button
          size="sm"
          variant="ghost"
          onClick={() => {
            const next = parentPath(path);
            setPath(next);
            void load(next);
          }}
          disabled={path === "."}
          title="上级目录"
        >
          <ArrowUp className="h-3.5 w-3.5" />
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => void load(path)}
          disabled={loading}
          title="刷新"
        >
          <RefreshCw className={cn("h-3.5 w-3.5", loading && "animate-spin")} />
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => setCreating((v) => !v)}
          title="新建目录"
        >
          <FolderPlus className="h-3.5 w-3.5" />
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => fileInputRef.current?.click()}
          title="上传文件"
        >
          <Upload className="h-3.5 w-3.5" />
        </Button>
        <input
          ref={fileInputRef}
          type="file"
          className="hidden"
          onChange={(event) => {
            const file = event.target.files?.[0];
            if (file) void handleUpload(file);
            event.target.value = "";
          }}
        />

        <span className="ml-2 truncate font-mono text-xs text-muted-foreground">{path}</span>
      </div>

      {creating ? (
        <div className="flex items-center gap-2">
          <Input
            value={newDir}
            onChange={(event) => setNewDir(event.target.value)}
            placeholder="目录名"
            className="h-8 max-w-xs text-xs"
            autoFocus
            onKeyDown={(event) => {
              if (event.key === "Enter") void handleMkdir();
              if (event.key === "Escape") setCreating(false);
            }}
          />
          <Button size="sm" onClick={() => void handleMkdir()}>
            创建
          </Button>
          <Button size="sm" variant="ghost" onClick={() => setCreating(false)}>
            取消
          </Button>
        </div>
      ) : null}

      {renaming ? (
        <div className="flex items-center gap-2">
          <Input
            value={renaming.name}
            onChange={(event) => setRenaming({ ...renaming, name: event.target.value })}
            className="h-8 max-w-xs text-xs"
            autoFocus
            onKeyDown={(event) => {
              if (event.key === "Enter") void handleRename();
              if (event.key === "Escape") setRenaming(null);
            }}
          />
          <Button size="sm" onClick={() => void handleRename()}>
            重命名
          </Button>
          <Button size="sm" variant="ghost" onClick={() => setRenaming(null)}>
            取消
          </Button>
        </div>
      ) : null}

      {/* 文件列表 */}
      <div className="min-h-0 flex-1 overflow-y-auto rounded-lg border border-border">
        {error ? (
          <p className="px-3 py-4 text-sm text-destructive">{error}</p>
        ) : loading && !entries ? (
          <div className="space-y-1 p-2">
            {[0, 1, 2, 3].map((index) => (
              <Skeleton key={index} className="h-9 w-full" />
            ))}
          </div>
        ) : entries && entries.length === 0 ? (
          <p className="px-3 py-8 text-center text-sm text-muted-foreground">空目录</p>
        ) : (
          entries?.map((entry) => (
            <div
              key={entry.path}
              className="group flex items-center gap-2.5 border-b border-border/50 px-3 py-2 text-sm last:border-b-0 hover:bg-accent/50"
            >
              {entry.isDir ? (
                <Folder className="h-4 w-4 shrink-0 text-amber-500" />
              ) : (
                <File className="h-4 w-4 shrink-0 text-muted-foreground" />
              )}

              <button
                type="button"
                onClick={() => {
                  if (entry.isDir) {
                    setPath(entry.path);
                    void load(entry.path);
                  }
                }}
                disabled={!entry.isDir}
                className="min-w-0 flex-1 truncate text-left disabled:cursor-default"
              >
                {entry.name}
              </button>

              <span className="w-20 shrink-0 text-right font-mono text-xs text-muted-foreground">
                {entry.isDir ? "—" : formatSize(entry.size)}
              </span>
              <span className="hidden w-28 shrink-0 text-right text-xs text-muted-foreground sm:block">
                {formatTime(entry.modified)}
              </span>

              <span className="flex shrink-0 items-center opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                {!entry.isDir ? (
                  <button
                    type="button"
                    onClick={() => void handleDownload(entry)}
                    title="下载"
                    className="rounded p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
                  >
                    <Download className="h-3.5 w-3.5" />
                  </button>
                ) : null}
                <button
                  type="button"
                  onClick={() => setRenaming({ path: entry.path, name: entry.name })}
                  title="重命名"
                  className="rounded p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
                >
                  <Pencil className="h-3.5 w-3.5" />
                </button>
                <button
                  type="button"
                  onClick={() => void handleDelete(entry)}
                  title="删除"
                  className="rounded p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}