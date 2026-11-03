import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import {
  AlertTriangle,
  Database,
  Download,
  HardDriveDownload,
  RotateCcw,
  Trash2,
  Upload,
} from "lucide-react";
import { toast } from "sonner";
import type { BackupFile } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { hasLocalApi } from "@/lib/desktop";
import { getTauriInvoke } from "@/lib/tauri-invoke";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { useAuth } from "@/lib/auth-session";
import { formatDateTime } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";

/** 备份文件大小，保留一位小数。 */
function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/** 相对时间：刚刚 / 3 分钟前 / 2 天前。 */
function relativeTime(timestamp: number): string {
  const diff = Date.now() - timestamp;
  if (diff < 0) return "刚刚";
  if (diff < 60_000) return "刚刚";
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)} 分钟前`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)} 小时前`;
  if (diff < 2_592_000_000) return `${Math.floor(diff / 86_400_000)} 天前`;
  // 超过 30 天就直接显示日期，比「87 天前」好读
  return formatDateTime(timestamp);
}

/** 网页端选文件：用完就移除 input，不留在 DOM 里。 */
function pickFileFromBrowser(): Promise<{ blob: Blob; name: string } | null> {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".bak,application/octet-stream";

    input.onchange = () => {
      const file = input.files?.[0];
      resolve(file ? { blob: file, name: file.name } : null);
    };
    // 用户点取消时不会触发 change，用焦点回归兜底
    input.oncancel = () => resolve(null);

    input.click();
  });
}

/** 恢复操作需要输入的确认词。 */
const CONFIRM_WORD = "RESTORE";

/**
 * 数据备份与恢复。
 *
 * 这个面板做的都是不可逆操作，所以每次都要二次确认，
 * 恢复更是要求手动输入确认词 —— 数据库被替换后，
 * 期间产生的所有数据（服务器配置、设置变更）都会消失。
 */
export function BackupPanel() {
  const api = useApi();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const sourceKey = useCurrentSourceKey();
  const setAuth = useAuth((state) => state.setAuth);

  const backups = useQuery({
    queryKey: [...queryKeys.settings(sourceKey), "backups"],
    queryFn: () => api.listBackups(),
  });

  const [busy, setBusy] = React.useState<string | null>(null);
  const [pendingDelete, setPendingDelete] = React.useState<BackupFile | null>(null);
  const [pendingRestore, setPendingRestore] = React.useState<BackupFile | null>(null);
  const [confirmText, setConfirmText] = React.useState("");

  const refresh = () =>
    queryClient.invalidateQueries({ queryKey: [...queryKeys.settings(sourceKey), "backups"] });

  async function createBackup() {
    setBusy("create");
    try {
      await api.createBackup();
      toast.success("备份已创建");
      await refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "备份失败");
    } finally {
      setBusy(null);
    }
  }

  async function confirmDelete() {
    const target = pendingDelete;
    setPendingDelete(null);
    if (!target) return;

    setBusy(target.name);
    try {
      await api.deleteBackup(target.name);
      toast.success("已删除");
      await refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "删除失败");
    } finally {
      setBusy(null);
    }
  }

  async function confirmRestore() {
    const target = pendingRestore;
    if (!target || confirmText !== CONFIRM_WORD) return;

    setPendingRestore(null);
    setConfirmText("");
    setBusy(target.name);

    try {
      const result = await api.restoreBackup(target.name);
      toast.success(
        `已恢复到 ${relativeTime(target.createdAt)}的备份。当前数据已保存为 ${result.safetyCopy}`,
        { duration: 5000 },
      );
      /*
       * 恢复后整个数据库被替换，sessions 表也在其中 ——
       * 当前令牌在新库里不存在，必须重新登录。
       *
       * 注意：账户本身**没有丢**。备份里如果包含账号，
       * 恢复后原用户名和密码照常可用，只是需要重新登录一次。
       * 下面的提示要把这点说清楚，避免用户以为要重新注册。
       */
      setAuth(null);
      /*
       * toast 挂在 body 上，跨路由不会消失 ——
       * 用足够长的持续时间让用户在登录页还能看到它。
       */
      toast.info("账户未变，请用原账号密码登录", { duration: 8000 });
      await navigate({ to: "/login", replace: true });
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "恢复失败");
      setBusy(null);
    }
  }

  /**
   * 下载备份。
   *
   * 两个平台路径不同：
   * - 网页端：window.open 交给浏览器下载
   * - 桌面端：WebView 里相对路径会解析成 tauri:// 而 404，
   *   必须自己取字节流，再让用户选保存位置后由 Rust 写盘
   */
  async function download(file: BackupFile) {
    setBusy(file.name);
    try {
      if (!hasLocalApi()) {
        // 网页端：交给浏览器下载
        const url = api.backupDownloadUrl?.(file.name);
        if (url) window.open(url, "_blank", "noopener");
        else toast.error("当前环境不支持下载备份");
        return;
      }

      // 桌面端：选路径 -> Rust 直接写盘
      const invoke = getTauriInvoke();
      if (!invoke) throw new Error("桌面端能力不可用");
      const target = await invoke<string | null>("backup_save_dialog", { name: file.name });
      if (!target) return; // 用户取消

      await invoke("backup_export", { name: file.name, target });
      toast.success(`已保存到 ${target}`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "下载失败");
    } finally {
      setBusy(null);
    }
  }

  /**
   * 导入外部备份。
   *
   * 两个平台选文件的方式不同：
   * - 网页端：隐藏的 <input type="file">
   * - 桌面端：Rust 的打开对话框，然后直接写盘（不经浏览器）
   */
  async function importFile() {
    setBusy("import");
    try {
      if (hasLocalApi()) {
        const invoke = getTauriInvoke();
        if (!invoke) throw new Error("桌面端能力不可用");

        const source = await invoke<string | null>("backup_pick_file");
        if (!source) return; // 用户取消

        const file = await invoke<BackupFile>("backup_import", { source });
        toast.success(`已导入 ${file.name}`);
      } else {
        const picked = await pickFileFromBrowser();
        if (!picked) return;

        const file = await api.importBackup(picked.blob, picked.name);
        toast.success(`已导入 ${file.file.name}`);
      }

      await refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "导入失败");
    } finally {
      setBusy(null);
    }
  }

  const files = backups.data?.files ?? [];

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Database className="h-4 w-4 text-primary" />
            数据库
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {backups.isLoading ? (
            <Skeleton className="h-16 w-full" />
          ) : (
            <dl className="grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt className="text-muted-foreground">文件大小</dt>
                <dd className="font-medium">{formatSize(backups.data?.databaseSize ?? 0)}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground">结构版本</dt>
                <dd className="font-medium">v{backups.data?.schemaVersion ?? "—"}</dd>
              </div>
            </dl>
          )}

          <div className="flex items-center gap-2">
            <Button size="sm" onClick={() => void createBackup()} disabled={busy !== null}>
              <HardDriveDownload className="h-4 w-4" />
              立即备份
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => void importFile()}
              disabled={busy !== null}
            >
              <Upload className="h-4 w-4" />
              导入备份
            </Button>
            <p className="text-xs text-muted-foreground">
              升级前会自动备份，备份永久保留。导入的备份会按本机库名重命名。
            </p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between gap-2">
            <span className="flex items-center gap-2">
              <RotateCcw className="h-4 w-4 text-primary" />
              备份文件
            </span>
            {files.length > 0 ? (
              <span className="text-xs font-normal text-muted-foreground">
                {files.length} 个 · 共 {formatSize(backups.data?.totalSize ?? 0)}
              </span>
            ) : null}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {backups.isLoading ? (
            <div className="space-y-2">
              <Skeleton className="h-14 w-full" />
              <Skeleton className="h-14 w-full" />
            </div>
          ) : files.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              还没有备份。可以点上面的「立即备份」手动创建一份。
            </p>
          ) : (
            <ul className="divide-y divide-border">
              {files.map((file) => (
                <li key={file.name} className="flex items-center gap-3 py-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-mono text-xs">{file.name}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      v{file.version} · {formatSize(file.size)} · {relativeTime(file.createdAt)}
                      <span className="ml-1 opacity-60">（{formatDateTime(file.createdAt)}）</span>
                    </p>
                  </div>

                  <div className="flex shrink-0 items-center gap-1">
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => void download(file)}
                      disabled={busy !== null}
                      title="下载到本地"
                    >
                      <Download className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setConfirmText("");
                        setPendingRestore(file);
                      }}
                      disabled={busy !== null}
                      title="从这个备份恢复"
                    >
                      <RotateCcw className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => setPendingDelete(file)}
                      disabled={busy !== null}
                      title="删除这个备份"
                      className="text-muted-foreground hover:text-destructive"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      {/* 删除确认 */}
      <Dialog
        open={pendingDelete !== null}
        onOpenChange={(open) => !open && setPendingDelete(null)}
      >
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>删除这个备份？</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            将永久删除{" "}
            <span className="break-all font-mono text-xs text-foreground">
              {pendingDelete?.name}
            </span>
            ，此操作无法撤销。
          </p>
          <DialogFooter>
            <Button size="sm" variant="ghost" onClick={() => setPendingDelete(null)}>
              取消
            </Button>
            <Button size="sm" variant="destructive" onClick={() => void confirmDelete()}>
              删除
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 恢复确认：需要输入确认词 */}
      <Dialog
        open={pendingRestore !== null}
        onOpenChange={(open) => {
          if (!open) {
            setPendingRestore(null);
            setConfirmText("");
          }
        }}
      >
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-4 w-4 text-destructive" />
              恢复到这个备份？
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-3 text-sm">
            <p className="text-muted-foreground">
              将用 <span className="font-mono text-xs text-foreground">{pendingRestore?.name}</span>{" "}
              覆盖当前数据库。备份之后新增的服务器、改过的设置都会消失。
            </p>
            <p className="text-muted-foreground">
              当前数据会先自动存一份，文件名会告诉你放在哪里。
            </p>
            <div className="space-y-1.5">
              <label htmlFor="restore-confirm" className="text-xs text-muted-foreground">
                输入 <span className="font-mono font-medium text-foreground">{CONFIRM_WORD}</span>{" "}
                确认
              </label>
              <Input
                id="restore-confirm"
                value={confirmText}
                onChange={(event) => setConfirmText(event.target.value)}
                placeholder={CONFIRM_WORD}
                autoComplete="off"
                className="font-mono"
              />
            </div>
          </div>

          <DialogFooter>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                setPendingRestore(null);
                setConfirmText("");
              }}
            >
              取消
            </Button>
            <Button
              size="sm"
              variant="destructive"
              disabled={confirmText !== CONFIRM_WORD}
              onClick={() => void confirmRestore()}
            >
              恢复
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
