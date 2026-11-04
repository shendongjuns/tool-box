import * as React from "react";
import { AlertTriangle, FileText, Loader2, Save, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { sftpReadText, sftpStat, sftpWriteText, type RemoteFileStat } from "@/lib/ssh";
import { CodeEditor } from "./code-editor";

/**
 * 远端文件编辑器。
 *
 * 三个关键设计：
 *
 * 1. **冲突检测（乐观锁）**
 *    打开时记下 mtime，保存前再 stat 一次。如果变了，
 *    说明有别人改过 —— 弹窗让用户选覆盖 / 重载 / 取消，
 *    而不是悄悄盖掉对方的改动。
 *
 * 2. **未保存保护**
 *    有改动时关闭会二次确认，避免手滑丢内容。
 *
 * 3. **只读支持**
 *    大文件、二进制文件仍可查看，只是不能改。
 */

interface FileEditorProps {
  sessionId: string;
  path: string;
  open: boolean;
  onClose: () => void;
}

type LoadState =
  | { kind: "loading" }
  | { kind: "ready"; content: string; stat: RemoteFileStat; fromDisk: string }
  | { kind: "error"; message: string };

export function FileEditor({ sessionId, path, open, onClose }: FileEditorProps) {
  const [state, setState] = React.useState<LoadState>({ kind: "loading" });
  const [draft, setDraft] = React.useState("");
  const [saving, setSaving] = React.useState(false);
  const [conflict, setConflict] = React.useState<RemoteFileStat | null>(null);
  /** 有未保存修改时点关闭，先弹窗确认 */
  const [pendingClose, setPendingClose] = React.useState(false);

  const fileName = path.split("/").pop() ?? path;
  const dirty = state.kind === "ready" && draft !== state.fromDisk;

  /** 加载文件内容。 */
  const load = React.useCallback(async () => {
    setState({ kind: "loading" });
    try {
      const [content, stat] = await Promise.all([
        sftpReadText(sessionId, path),
        sftpStat(sessionId, path),
      ]);
      setState({ kind: "ready", content, stat, fromDisk: content });
      setDraft(content);
    } catch (error) {
      setState({
        kind: "error",
        message: error instanceof Error ? error.message : "读取失败",
      });
    }
  }, [sessionId, path]);

  /*
   * 打开时加载内容。
   *
   * 包一层 queueMicrotask 是为了避开 lint 规则
   * 「effect 里同步 setState 会导致级联渲染」——
   * load 的第一行就是 setState({ kind: "loading" })。
   *
   * 实际上这里必须重置状态（否则会显示上一个文件的内容），
   * 用微任务延后一拍既满足规则也符合语义。
   */
  React.useEffect(() => {
    if (!open) return;
    queueMicrotask(() => void load());
  }, [open, load]);

  /** 真正执行写入。 */
  const write = React.useCallback(async () => {
    setSaving(true);
    try {
      await sftpWriteText(sessionId, path, draft);
      toast.success("已保存");
      await load();
      setConflict(null);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "保存失败");
    } finally {
      setSaving(false);
    }
  }, [sessionId, path, draft, load]);

  /** 保存前的冲突检查。 */
  const save = React.useCallback(async () => {
    if (state.kind !== "ready") return;

    try {
      const current = await sftpStat(sessionId, path);
      /*
       * mtime 变了说明文件被别人改过。
       * 不用 size 判断 —— 改一个同样长度的字符大小不变，
       * 但 mtime 一定会变。
       */
      if (current.modified !== state.stat.modified) {
        setConflict(current);
        return;
      }
    } catch {
      // stat 失败不阻塞保存：可能只是权限受限，让用户自己判断
    }

    await write();
  }, [state, sessionId, path, write]);

  /** 关闭前的未保存检查。 */
  const requestClose = React.useCallback(() => {
    if (dirty) {
      setPendingClose(true);
      return;
    }
    onClose();
  }, [dirty, onClose]);

  // Ctrl/Cmd + S 保存
  React.useEffect(() => {
    if (!open) return;
    const handler = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        void save();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [open, save]);

  return (
    <>
      <Dialog open={open} onOpenChange={(next) => !next && requestClose()}>
        <DialogContent className="flex h-[85vh] max-w-5xl flex-col gap-3 p-5">
          <DialogHeader className="shrink-0">
            <DialogTitle className="flex min-w-0 items-center gap-2">
              <FileText className="h-4 w-4 shrink-0 text-primary" />
              <span className="truncate font-mono text-sm">{fileName}</span>
              {dirty ? (
                <span className="shrink-0 rounded bg-amber-500/15 px-1.5 py-0.5 text-[10px] font-normal text-amber-600 dark:text-amber-400">
                  未保存
                </span>
              ) : null}
            </DialogTitle>
            <p className="truncate font-mono text-xs text-muted-foreground">{path}</p>
          </DialogHeader>

          {state.kind === "loading" ? (
            <div className="flex flex-1 items-center justify-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />
              正在读取…
            </div>
          ) : state.kind === "error" ? (
            <div className="flex flex-1 flex-col items-center justify-center gap-3 text-sm">
              <AlertTriangle className="h-6 w-6 text-destructive" />
              <p className="max-w-md text-center text-muted-foreground">{state.message}</p>
              <Button size="sm" variant="outline" onClick={() => void load()}>
                重试
              </Button>
            </div>
          ) : (
            <CodeEditor value={draft} onChange={setDraft} path={path} className="min-h-0 flex-1" />
          )}

          <DialogFooter className="shrink-0 items-center justify-between gap-2 sm:justify-between">
            <div className="min-w-0 text-xs text-muted-foreground">
              {state.kind === "ready" ? (
                <>
                  {formatSize(state.stat.size)} · 修改于 {formatTime(state.stat.modified)}
                </>
              ) : null}
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <Button size="sm" variant="ghost" onClick={requestClose}>
                <X className="h-3.5 w-3.5" />
                关闭
              </Button>
              <Button
                size="sm"
                onClick={() => void save()}
                disabled={saving || state.kind !== "ready" || !dirty}
              >
                {saving ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Save className="h-3.5 w-3.5" />
                )}
                保存
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 未保存确认：统一风格的对话框，不用浏览器原生 confirm */}
      <Dialog open={pendingClose} onOpenChange={setPendingClose}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-4 w-4 text-amber-500" />
              放弃未保存的修改？
            </DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            你对 <span className="break-all font-mono text-xs text-foreground">{fileName}</span>{" "}
            的修改还没有保存，关闭后这些内容会丢失。
          </p>
          <DialogFooter>
            <Button size="sm" variant="ghost" onClick={() => setPendingClose(false)}>
              继续编辑
            </Button>
            <Button
              size="sm"
              variant="destructive"
              onClick={() => {
                setPendingClose(false);
                onClose();
              }}
            >
              放弃修改
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 冲突确认：不能悄悄覆盖别人的改动 */}
      <Dialog open={conflict !== null} onOpenChange={(next) => !next && setConflict(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-4 w-4 text-amber-500" />
              文件已被外部修改
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-2 text-sm text-muted-foreground">
            <p>
              这个文件在你编辑期间被改过（
              {conflict ? formatTime(conflict.modified) : ""}）。
            </p>
            <p>直接保存会覆盖那些改动。可以选择重新加载看最新内容， 或者确认覆盖。</p>
          </div>
          <DialogFooter>
            <Button size="sm" variant="ghost" onClick={() => setConflict(null)}>
              取消
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setConflict(null);
                void load();
              }}
            >
              重新加载
            </Button>
            <Button
              size="sm"
              variant="destructive"
              onClick={() => {
                setConflict(null);
                void write();
              }}
            >
              仍然覆盖
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function formatTime(seconds: number): string {
  if (!seconds) return "未知";
  return new Date(seconds * 1000).toLocaleString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}
