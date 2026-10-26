import * as React from "react";
import {
  ArrowUp,
  ChevronRight,
  Download,
  File,
  Folder,
  FolderPlus,
  Home,
  Pencil,
  RefreshCw,
  Shield,
  Trash2,
  Upload,
  X,
} from "lucide-react";
import { toast } from "sonner";
import {
  base64ToBlob,
  readLocalFileAsBase64,
  remoteHomeDir,
  sftpChmod,
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
  return new Date(seconds * 1000).toLocaleString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** 权限位转 rwx 字符串。 */
function modeToRwx(mode: string): string {
  const value = Number.parseInt(mode, 8) || 0;
  const bit = (shift: number, char: string) => ((value >> shift) & 1 ? char : "-");
  const triple = (shift: number) =>
    `${bit(shift + 2, "r")}${bit(shift + 1, "w")}${bit(shift, "x")}`;
  return `${triple(6)}${triple(3)}${triple(0)}`;
}

/** 下载任务。 */
interface DownloadTask {
  id: string;
  name: string;
  path: string;
  status: "pending" | "downloading" | "done" | "failed";
  progress: number;
  size: number;
  error?: string;
}

/** SFTP 文件浏览器。 */
export function SftpPanel({ sessionId }: { sessionId: string }) {
  const [path, setPath] = React.useState("");
  const [pathInput, setPathInput] = React.useState("");
  const [editingPath, setEditingPath] = React.useState(false);
  const [entries, setEntries] = React.useState<SftpEntry[] | null>(null);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [creating, setCreating] = React.useState(false);
  const [newDir, setNewDir] = React.useState("");
  const [renaming, setRenaming] = React.useState<{ path: string; name: string } | null>(null);
  const [chmodTarget, setChmodTarget] = React.useState<SftpEntry | null>(null);
  const [chmodValue, setChmodValue] = React.useState("644");
  const [downloads, setDownloads] = React.useState<DownloadTask[]>([]);
  const [showDownloads, setShowDownloads] = React.useState(false);
  const fileInputRef = React.useRef<HTMLInputElement>(null);

  // 首次进入取远端 home 目录（绝对路径）
  React.useEffect(() => {
    let cancelled = false;
    void (async () => {
      const home = await remoteHomeDir(sessionId);
      if (cancelled) return;
      setPath(home);
      setPathInput(home);
    })();
    return () => {
      cancelled = true;
    };
  }, [sessionId]);

  const load = React.useCallback(
    async (target: string) => {
      try {
        const list = await sftpList(sessionId, target || ".");
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
    if (!path) return;
    const timer = window.setTimeout(() => {
      setLoading(true);
      void load(path);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [path, load]);

  function navigate(target: string) {
    setPath(target);
    setPathInput(target);
    setEditingPath(false);
  }

  function goUp() {
    const trimmed = path.replace(/\/$/, "");
    const index = trimmed.lastIndexOf("/");
    navigate(index <= 0 ? "/" : trimmed.slice(0, index));
  }

  function submitPath() {
    const next = pathInput.trim();
    if (!next) return;
    navigate(next.startsWith("/") ? next : `${path}/${next}`);
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
    const target = `${path.replace(/\/$/, "")}/${renaming.name}`;
    try {
      await sftpRename(sessionId, renaming.path, target);
      toast.success("已重命名");
      setRenaming(null);
      await load(path);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "重命名失败");
    }
  }

  async function handleChmod() {
    if (!chmodTarget) return;
    const mode = Number.parseInt(chmodValue, 8);
    if (!Number.isFinite(mode)) {
      toast.error("权限需要用八进制，例如 644");
      return;
    }
    try {
      await sftpChmod(sessionId, chmodTarget.path, mode);
      toast.success(`权限已改为 ${chmodValue}`);
      setChmodTarget(null);
      await load(path);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "修改权限失败");
    }
  }

  async function handleMkdir() {
    if (!newDir.trim()) return;
    const target = `${path.replace(/\/$/, "")}/${newDir.trim()}`;
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

  /** 下载：建立任务、更新进度、触发浏览器保存。 */
  async function handleDownload(entry: SftpEntry) {
    const taskId = `dl-${Date.now()}`;
    setDownloads((prev) => [
      ...prev,
      {
        id: taskId,
        name: entry.name,
        path: entry.path,
        status: "downloading",
        progress: 10,
        size: entry.size,
      },
    ]);
    setShowDownloads(true);

    const patch = (next: Partial<DownloadTask>) =>
      setDownloads((prev) =>
        prev.map((item) => (item.id === taskId ? { ...item, ...next } : item)),
      );

    try {
      // SFTP 读取是一次性拿全量，这里用阶段进度反映实际过程
      patch({ progress: 45 });
      const base64 = await sftpRead(sessionId, entry.path);
      patch({ progress: 85 });

      const blob = base64ToBlob(base64);
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = entry.name;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      // 延迟回收，避免下载被中断
      window.setTimeout(() => URL.revokeObjectURL(url), 60_000);

      patch({ status: "done", progress: 100 });
    } catch (err) {
      patch({
        status: "failed",
        error: err instanceof Error ? err.message : "下载失败",
        progress: 100,
      });
    }
  }

  async function handleUpload(file: File) {
    try {
      const base64 = await readLocalFileAsBase64(file);
      const target = `${path.replace(/\/$/, "")}/${file.name}`;
      await sftpWrite(sessionId, target, base64);
      toast.success(`已上传 ${file.name}`);
      await load(path);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "上传失败");
    }
  }

  const activeDownloads = downloads.filter((task) => task.status === "downloading").length;

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2">
      {/* 路径栏：可编辑跳转 */}
      <div className="flex items-center gap-1.5">
        <Button size="sm" variant="ghost" onClick={goUp} disabled={path === "/"} title="上级目录">
          <ArrowUp className="h-3.5 w-3.5" />
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => navigate("/")}
          title="根目录"
        >
          <Home className="h-3.5 w-3.5" />
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

        {/* 绝对路径输入 */}
        <div className="flex min-w-0 flex-1 items-center gap-1 rounded-md border border-input bg-[var(--card)] px-2">
          <ChevronRight className="h-3 w-3 shrink-0 text-muted-foreground/50" />
          {editingPath ? (
            <input
              value={pathInput}
              onChange={(event) => setPathInput(event.target.value)}
              onBlur={submitPath}
              onKeyDown={(event) => {
                if (event.key === "Enter") submitPath();
                if (event.key === "Escape") {
                  setPathInput(path);
                  setEditingPath(false);
                }
              }}
              autoFocus
              spellCheck={false}
              className="h-7 w-full bg-transparent font-mono text-xs outline-none"
            />
          ) : (
            <button
              type="button"
              onClick={() => setEditingPath(true)}
              title="点击编辑路径"
              className="h-7 w-full truncate text-left font-mono text-xs text-muted-foreground hover:text-foreground"
            >
              {path || "…"}
            </button>
          )}
        </div>

        <Button size="sm" variant="ghost" onClick={() => setCreating((v) => !v)} title="新建目录">
          <FolderPlus className="h-3.5 w-3.5" />
        </Button>
        <Button size="sm" variant="ghost" onClick={() => fileInputRef.current?.click()} title="上传">
          <Upload className="h-3.5 w-3.5" />
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => setShowDownloads((v) => !v)}
          title="下载列表"
          className={cn(activeDownloads > 0 && "text-primary")}
        >
          <Download className="h-3.5 w-3.5" />
          {downloads.length > 0 ? (
            <span className="ml-0.5 text-[10px] tabular-nums">{downloads.length}</span>
          ) : null}
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
      </div>

      {/* 下载列表 */}
      {showDownloads && downloads.length > 0 ? (
        <div className="rounded-lg border border-border bg-card p-2">
          <div className="mb-1 flex items-center justify-between">
            <span className="text-[11px] font-medium text-muted-foreground">下载列表</span>
            <button
              type="button"
              onClick={() => setDownloads([])}
              className="text-[10px] text-muted-foreground hover:text-foreground"
            >
              清空
            </button>
          </div>
          <div className="space-y-1.5">
            {downloads.map((task) => (
              <div key={task.id} className="space-y-1">
                <div className="flex items-center justify-between gap-2 text-[11px]">
                  <span className="min-w-0 flex-1 truncate">{task.name}</span>
                  <span
                    className={cn(
                      "shrink-0 tabular-nums",
                      task.status === "done" && "text-emerald-600 dark:text-emerald-400",
                      task.status === "failed" && "text-destructive",
                      task.status === "downloading" && "text-muted-foreground",
                    )}
                  >
                    {task.status === "done"
                      ? `完成 · ${formatSize(task.size)}`
                      : task.status === "failed"
                        ? `失败：${task.error ?? "未知"}`
                        : `${task.progress}%`}
                  </span>
                  <button
                    type="button"
                    onClick={() =>
                      setDownloads((prev) => prev.filter((item) => item.id !== task.id))
                    }
                    className="shrink-0 rounded p-0.5 text-muted-foreground hover:text-foreground"
                  >
                    <X className="h-3 w-3" />
                  </button>
                </div>
                <div className="h-1 overflow-hidden rounded-full bg-muted">
                  <div
                    className={cn(
                      "h-full rounded-full transition-all duration-300",
                      task.status === "failed"
                        ? "bg-destructive"
                        : task.status === "done"
                          ? "bg-emerald-500"
                          : "bg-primary",
                    )}
                    style={{ width: `${task.progress}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {/* 新建目录 / 重命名 / 权限 表单 */}
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
            保存
          </Button>
          <Button size="sm" variant="ghost" onClick={() => setRenaming(null)}>
            取消
          </Button>
        </div>
      ) : null}

      {chmodTarget ? (
        <div className="flex items-center gap-2">
          <span className="truncate text-xs text-muted-foreground">{chmodTarget.name}</span>
          <Input
            value={chmodValue}
            onChange={(event) => setChmodValue(event.target.value)}
            className="h-8 w-24 font-mono text-xs"
            autoFocus
            onKeyDown={(event) => {
              if (event.key === "Enter") void handleChmod();
              if (event.key === "Escape") setChmodTarget(null);
            }}
          />
          <span className="text-[10px] text-muted-foreground">八进制，如 644 / 755</span>
          <Button size="sm" onClick={() => void handleChmod()}>
            应用
          </Button>
          <Button size="sm" variant="ghost" onClick={() => setChmodTarget(null)}>
            取消
          </Button>
        </div>
      ) : null}

      {/* 文件列表 */}
      <div className="min-h-0 flex-1 overflow-y-auto rounded-lg border border-border">
        {/* 表头 */}
        <div className="sticky top-0 z-10 flex items-center gap-2 border-b border-border bg-card px-3 py-1.5 text-[10px] font-medium text-muted-foreground">
          <span className="w-4 shrink-0" />
          <span className="min-w-0 flex-1">名称</span>
          <span className="w-24 shrink-0">权限</span>
          <span className="w-20 shrink-0 text-right">大小</span>
          <span className="w-28 shrink-0 text-right">修改时间</span>
          <span className="w-20 shrink-0" />
        </div>

        {error ? (
          <p className="px-3 py-4 text-sm text-destructive">{error}</p>
        ) : loading && !entries ? (
          <div className="space-y-1 p-2">
            {[0, 1, 2, 3].map((index) => (
              <Skeleton key={index} className="h-8 w-full" />
            ))}
          </div>
        ) : entries && entries.length === 0 ? (
          <p className="px-3 py-8 text-center text-sm text-muted-foreground">空目录</p>
        ) : (
          entries?.map((entry) => (
            <div
              key={entry.path}
              className="group flex items-center gap-2 border-b border-border/40 px-3 py-1.5 text-sm last:border-b-0 hover:bg-accent/50"
            >
              {entry.isDir ? (
                <Folder className="h-4 w-4 shrink-0 text-amber-500" />
              ) : (
                <File className="h-4 w-4 shrink-0 text-muted-foreground" />
              )}

              <button
                type="button"
                onClick={() => {
                  if (entry.isDir) navigate(entry.path);
                }}
                disabled={!entry.isDir}
                className="min-w-0 flex-1 truncate text-left disabled:cursor-default"
              >
                {entry.name}
              </button>

              {/* 权限：rwx + 八进制 */}
              <span
                className="w-24 shrink-0 font-mono text-[10px] text-muted-foreground"
                title={`拥有者权限 ${modeToRwx(entry.mode)}`}
              >
                {modeToRwx(entry.mode)}{" "}
                <span className="text-muted-foreground/60">{entry.mode}</span>
              </span>

              <span className="w-20 shrink-0 text-right font-mono text-[11px] text-muted-foreground">
                {entry.isDir ? "—" : formatSize(entry.size)}
              </span>
              <span className="w-28 shrink-0 text-right text-[11px] text-muted-foreground">
                {formatTime(entry.modified)}
              </span>

              <span className="flex w-20 shrink-0 items-center justify-end gap-0.5 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
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
                  onClick={() => {
                    setChmodTarget(entry);
                    setChmodValue(entry.mode);
                  }}
                  title="修改权限"
                  className="rounded p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
                >
                  <Shield className="h-3.5 w-3.5" />
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
