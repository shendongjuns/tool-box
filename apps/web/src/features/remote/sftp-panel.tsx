import * as React from "react";
import {
  ArrowUp,
  ChevronRight,
  Download,
  File,
  Folder,
  FolderPlus,
  Home,
  MoreHorizontal,
  Pencil,
  RefreshCw,
  Shield,
  Trash2,
  Upload,
  X,
} from "lucide-react";
import { toast } from "sonner";
import {
  pickOpenPath,
  pickSavePath,
  remoteHomeDir,
  sftpChmod,
  sftpDownload,
  sftpList,
  sftpMkdir,
  sftpRemove,
  sftpRename,
  sftpUpload,
  subscribeTransferProgress,
  type SftpEntry,
} from "@/lib/ssh";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { ContextMenu } from "@/components/ui/context-menu";
import { useTransfers } from "./transfer-store";

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

/** 时间精确到秒，含年份。 */
function formatTime(seconds: number): string {
  if (!seconds) return "—";
  const date = new Date(seconds * 1000);
  const pad = (n: number) => String(n).padStart(2, "0");
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
  );
}

/** 权限位转 rwx 字符串。 */
function modeToRwx(mode: string): string {
  const value = Number.parseInt(mode, 8) || 0;
  const bit = (shift: number, char: string) => ((value >> shift) & 1 ? char : "-");
  const triple = (shift: number) =>
    `${bit(shift + 2, "r")}${bit(shift + 1, "w")}${bit(shift, "x")}`;
  return `${triple(6)}${triple(3)}${triple(0)}`;
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
  /** 行内重命名：正在编辑的条目路径与输入值 */
  const [renaming, setRenaming] = React.useState<{ path: string; value: string } | null>(null);
  /** 行内改权限：正在编辑的条目路径与八进制输入 */
  const [chmod, setChmod] = React.useState<{ path: string; value: string } | null>(null);
  /** 右键菜单位置与目标条目 */
  const [menu, setMenu] = React.useState<{ x: number; y: number; entry: SftpEntry } | null>(null);
  const { tasks: transfers, add, patch, remove, clearFinished } = useTransfers();
  const [showTransfers, setShowTransfers] = React.useState(false);

  // 首次进入取远端 home 目录
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

  // 订阅传输进度
  React.useEffect(() => {
    let cancelled = false;
    let off: (() => void) | null = null;

    void (async () => {
      const unsubscribe = await subscribeTransferProgress((payload) => {
        const current = useTransfers.getState().tasks.find((item) => item.id === payload.taskId);
        patch(payload.taskId, {
          transferred: payload.transferred,
          total: payload.total || current?.total || 0,
          percent: payload.percent,
        });
      });
      if (cancelled) unsubscribe();
      else off = unsubscribe;
    })();

    return () => {
      cancelled = true;
      off?.();
    };
  }, [patch]);

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

  /** 行内重命名：提交时把新名字拼回同一目录。 */
  async function submitRename() {
    if (!renaming) return;
    const name = renaming.value.trim();
    const original = renaming.path;
    setRenaming(null);
    if (!name || `${path.replace(/\/$/, "")}/${name}` === original) return;

    const target = `${path.replace(/\/$/, "")}/${name}`;
    try {
      await sftpRename(sessionId, original, target);
      toast.success("已重命名");
      await load(path);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "重命名失败");
    }
  }

  /** 行内改权限。 */
  async function submitChmod() {
    if (!chmod) return;
    const value = chmod.value.trim();
    const target = chmod.path;
    setChmod(null);

    const mode = Number.parseInt(value, 8);
    if (!Number.isFinite(mode)) {
      toast.error("权限需要用八进制，例如 644");
      return;
    }
    try {
      await sftpChmod(sessionId, target, mode);
      toast.success(`权限已改为 ${value}`);
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

  /** 下载：先选保存路径，再由 Rust 直连传输。 */
  const handleDownload = React.useCallback(async (entry: SftpEntry) => {
    const localPath = await pickSavePath(entry.name);
    if (!localPath) return;

    const now = Date.now();
    const taskId = `dl-${now.toString(36)}`;
    add({
      id: taskId,
      name: entry.name,
      direction: "download",
      remoteDir: path,
      localPath,
      transferred: 0,
      total: entry.size,
      percent: 0,
      status: "running",
      createdAt: now,
    });
    // 不自动弹窗：用户需要时自己打开传输列表
    toast.info(`开始下载 ${entry.name}`, { description: `保存到 ${localPath}` });

    try {
      await sftpDownload(sessionId, entry.path, localPath, taskId);
      patch(taskId, { status: "done", percent: 100 });
      toast.success(`已下载 ${entry.name}`, { description: `保存到 ${localPath}` });
    } catch (err) {
      const message = err instanceof Error ? err.message : "下载失败";
      patch(taskId, { status: "failed", error: message });
      toast.error(message);
    }
  }, [add, patch, path, sessionId]);

  /** 上传：先选本地文件，再由 Rust 直连传输。 */
  const handleUpload = React.useCallback(async () => {
    const localPath = await pickOpenPath();
    if (!localPath) return;

    const name = localPath.split(/[/\\]/).pop() ?? "file";
    const remotePath = `${path.replace(/\/$/, "")}/${name}`;
    const now = Date.now();
    const taskId = `ul-${now.toString(36)}`;

    add({
      id: taskId,
      name,
      direction: "upload",
      remoteDir: path,
      localPath,
      transferred: 0,
      total: 0,
      percent: 0,
      status: "running",
      createdAt: now,
    });
    toast.info(`开始上传 ${name}`, { description: `目标 ${path}` });

    try {
      await sftpUpload(sessionId, localPath, remotePath, taskId);
      patch(taskId, { status: "done", percent: 100 });
      toast.success(`已上传 ${name}`, { description: `目标 ${path}` });
      await load(path);
    } catch (err) {
      const message = err instanceof Error ? err.message : "上传失败";
      patch(taskId, { status: "failed", error: message });
      toast.error(message);
    }
  }, [add, patch, path, sessionId, load]);

  const runningCount = transfers.filter((task) => task.status === "running").length;

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-hidden">
      {/* 路径栏 */}
      <div className="flex items-center gap-1.5">
        <Button size="sm" variant="ghost" onClick={goUp} disabled={path === "/"} title="上级目录">
          <ArrowUp className="h-3.5 w-3.5" />
        </Button>
        <Button size="sm" variant="ghost" onClick={() => navigate("/")} title="根目录">
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
        <Button size="sm" variant="ghost" onClick={() => void handleUpload()} title="上传">
          <Upload className="h-3.5 w-3.5" />
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => setShowTransfers(true)}
          title="传输列表"
          className={cn(runningCount > 0 && "text-primary")}
        >
          <Download className="h-3.5 w-3.5" />
          {transfers.length > 0 ? (
            <span className="ml-0.5 text-[10px] tabular-nums">
              {runningCount > 0 ? `${runningCount}/${transfers.length}` : transfers.length}
            </span>
          ) : null}
        </Button>
      </div>

      {/* 表单区 */}
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

      {/* 文件列表 */}
      <div className="min-h-0 flex-1 overflow-y-auto rounded-lg border border-border">
        {/* 表头：列宽与行一致，末列留出按钮空间 */}
        <div className="sticky top-0 z-10 flex items-center gap-2 border-b border-border bg-card px-3 py-1.5 text-[10px] font-medium text-muted-foreground">
          <span className="w-4 shrink-0" />
          <span className="min-w-0 flex-1">名称</span>
          <span className="w-28 shrink-0">权限</span>
          <span className="w-16 shrink-0 text-right">大小</span>
          <span className="w-40 shrink-0 text-right">修改时间</span>
          <span className="w-24 shrink-0" />
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
          entries?.map((entry) => {
            const isRenaming = renaming?.path === entry.path;
            const isChmod = chmod?.path === entry.path;

            return (
              <div
                key={entry.path}
                onDoubleClick={() => {
                  if (entry.isDir) navigate(entry.path);
                }}
                onContextMenu={(event) => {
                  event.preventDefault();
                  setMenu({ x: event.clientX, y: event.clientY, entry });
                }}
                className={cn(
                  "group flex items-center gap-2 border-b border-border/40 px-3 py-1.5 text-sm last:border-b-0",
                  menu?.entry.path === entry.path ? "bg-accent" : "hover:bg-accent/70",
                )}
              >
                {entry.isDir ? (
                  <Folder className="h-4 w-4 shrink-0 text-amber-500" />
                ) : (
                  <File className="h-4 w-4 shrink-0 text-muted-foreground" />
                )}

                {/* 名称：双击文件夹进入；右键出菜单；重命名时变输入框 */}
                {isRenaming ? (
                  <span className="flex min-w-0 flex-1 items-center gap-1">
                    <input
                      value={renaming.value}
                      onChange={(event) =>
                        setRenaming({ path: entry.path, value: event.target.value })
                      }
                      onBlur={() => void submitRename()}
                      onKeyDown={(event) => {
                        if (event.key === "Enter") void submitRename();
                        if (event.key === "Escape") setRenaming(null);
                      }}
                      autoFocus
                      spellCheck={false}
                      className="h-6 min-w-0 flex-1 rounded border border-primary/40 bg-background px-1.5 font-mono text-xs outline-none"
                    />
                  </span>
                ) : (
                  <span
                    className="min-w-0 flex-1 cursor-default select-none truncate"
                    title={entry.isDir ? "双击进入 · 右键更多" : "右键更多"}
                  >
                    {entry.name}
                  </span>
                )}

                {/* 权限：正常情况下显示；改权限时变输入框 */}
                {isChmod ? (
                  <span className="flex w-28 shrink-0 items-center gap-1">
                    <input
                      value={chmod.value}
                      onChange={(event) => setChmod({ path: entry.path, value: event.target.value })}
                      onBlur={() => void submitChmod()}
                      onKeyDown={(event) => {
                        if (event.key === "Enter") void submitChmod();
                        if (event.key === "Escape") setChmod(null);
                      }}
                      autoFocus
                      spellCheck={false}
                      placeholder="644"
                      className="h-6 w-full rounded border border-primary/40 bg-background px-1.5 font-mono text-xs outline-none"
                    />
                  </span>
                ) : (
                  <span
                    className="w-28 shrink-0 cursor-pointer font-mono text-[10px] text-muted-foreground hover:text-foreground"
                    title={`点击修改权限（当前 ${entry.mode}）`}
                    onClick={() => setChmod({ path: entry.path, value: entry.mode })}
                  >
                    {modeToRwx(entry.mode)}{" "}
                    <span className="text-muted-foreground/60">{entry.mode}</span>
                  </span>
                )}

                <span className="w-16 shrink-0 text-right font-mono text-[11px] text-muted-foreground">
                  {entry.isDir ? "—" : formatSize(entry.size)}
                </span>
                <span className="w-40 shrink-0 text-right font-mono text-[11px] text-muted-foreground">
                  {formatTime(entry.modified)}
                </span>

                {/* 操作栏精简为「更多」一个入口 */}
                <span className="flex w-8 shrink-0 justify-end">
                  <button
                    type="button"
                    title="更多"
                    aria-label={`${entry.name} 的更多操作`}
                    onClick={(event) => {
                      const rect = event.currentTarget.getBoundingClientRect();
                      setMenu({ x: rect.left, y: rect.bottom + 2, entry });
                    }}
                    className="rounded p-1 text-muted-foreground opacity-0 transition-opacity hover:bg-accent hover:text-foreground group-hover:opacity-100"
                  >
                    <MoreHorizontal className="h-3.5 w-3.5" />
                  </button>
                </span>
              </div>
            );
          })
        )}
      </div>

      {/* 右键菜单 */}
      {menu ? (
        <ContextMenu
          x={menu.x}
          y={menu.y}
          items={[
            ...(menu.entry.isDir
              ? [{ label: "打开", icon: Folder, onSelect: () => navigate(menu.entry.path) }]
              : [
                  {
                    label: "下载",
                    icon: Download,
                    onSelect: () => void handleDownload(menu.entry),
                  },
                ]),
            {
              label: "重命名",
              icon: Pencil,
              onSelect: () => setRenaming({ path: menu.entry.path, value: menu.entry.name }),
            },
            {
              label: "修改权限",
              icon: Shield,
              onSelect: () => setChmod({ path: menu.entry.path, value: menu.entry.mode }),
            },
            {
              label: "删除",
              icon: Trash2,
              destructive: true,
              onSelect: () => void handleDelete(menu.entry),
            },
          ]}
          onClose={() => setMenu(null)}
        />
      ) : null}

      {/* 传输列表：弹窗，不占用文件列表空间 */}
      <Dialog open={showTransfers} onOpenChange={setShowTransfers}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>传输列表</DialogTitle>
          </DialogHeader>

          {transfers.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">暂无传输任务</p>
          ) : (
            <div className="max-h-80 space-y-3 overflow-y-auto">
              {transfers.map((task) => (
                <div key={task.id} className="space-y-1">
                  <div className="flex items-center justify-between gap-2 text-xs">
                    <span className="flex min-w-0 flex-1 items-center gap-1.5">
                      {task.direction === "download" ? (
                        <Download className="h-3 w-3 shrink-0 text-muted-foreground" />
                      ) : (
                        <Upload className="h-3 w-3 shrink-0 text-muted-foreground" />
                      )}
                      <span className="truncate">{task.name}</span>
                    </span>
                    <span
                      className={cn(
                        "shrink-0 tabular-nums",
                        task.status === "done" && "text-emerald-600 dark:text-emerald-400",
                        task.status === "failed" && "text-destructive",
                        task.status === "running" && "text-muted-foreground",
                      )}
                    >
                      {task.status === "done"
                        ? `完成 · ${formatSize(task.total || task.transferred)}`
                        : task.status === "failed"
                          ? "失败"
                          : `${task.percent}%`}
                    </span>
                    <button
                      type="button"
                      onClick={() => remove(task.id)}
                      className="shrink-0 rounded p-0.5 text-muted-foreground hover:text-foreground"
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                  <div className="h-1 overflow-hidden rounded-full bg-muted">
                    <div
                      className={cn(
                        "h-full rounded-full transition-all duration-200",
                        task.status === "failed"
                          ? "bg-destructive"
                          : task.status === "done"
                            ? "bg-emerald-500"
                            : "bg-primary",
                      )}
                      style={{ width: `${task.percent}%` }}
                    />
                  </div>
                  {/* 传输位置：下载看保存路径，上传看目标目录 */}
                  <p
                    className="truncate font-mono text-[10px] text-muted-foreground/70"
                    title={task.direction === "download" ? task.localPath : task.remoteDir}
                  >
                    {task.direction === "download"
                      ? `→ ${task.localPath ?? "—"}`
                      : `→ ${task.remoteDir}/${task.name}`}
                  </p>
                  {task.error ? (
                    <p className="text-[10px] text-destructive">{task.error}</p>
                  ) : null}
                </div>
              ))}
            </div>
          )}

          <DialogFooter>
            <Button size="sm" variant="ghost" onClick={() => clearFinished()}>
              清空已完成
            </Button>
            <Button size="sm" onClick={() => setShowTransfers(false)}>
              关闭
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}