import * as React from "react";
import { toast } from "sonner";
import {
  hideToTray,
  listenCloseRequest,
  quitApp,
  readCloseBehavior,
  writeCloseBehavior,
  type CloseBehavior,
} from "@/lib/desktop-close";
import { isDesktop } from "@/lib/platform";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Switch } from "@/components/ui/switch";

/**
 * 关闭窗口时的行为。
 *
 * 默认「每次询问」：弹框让用户选「最小化到托盘」或「直接退出」，
 * 可勾选「记住我的选择」。选择会被持久化，下次直接执行。
 */
export function CloseGuard() {
  const [open, setOpen] = React.useState(false);
  const [remember, setRemember] = React.useState(false);
  const behaviorRef = React.useRef<CloseBehavior>("ask");

  React.useEffect(() => {
    if (!isDesktop()) return;
    behaviorRef.current = readCloseBehavior();

    let dispose: (() => void) | undefined;
    void listenCloseRequest(() => {
      const behavior = readCloseBehavior();
      if (behavior === "tray") {
        void hideToTray().then(() => toast.success("已最小化到托盘"));
        return;
      }
      if (behavior === "quit") {
        void quitApp();
        return;
      }
      setOpen(true);
    }).then((fn) => {
      dispose = fn;
    });

    return () => dispose?.();
  }, []);

  async function choose(behavior: Exclude<CloseBehavior, "ask">) {
    if (remember) writeCloseBehavior(behavior);
    setOpen(false);
    if (behavior === "tray") {
      await hideToTray();
      toast.success("已最小化到托盘，可从任务栏托盘图标恢复");
    } else {
      await quitApp();
    }
  }

  if (!isDesktop()) return null;

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>要关闭 ToolBox 吗？</DialogTitle>
          <DialogDescription>
            最小化到托盘可以让应用在后台继续运行；选择退出则会结束所有本地服务。
          </DialogDescription>
        </DialogHeader>

        <label className="flex items-center gap-2 rounded-lg border border-border px-3 py-2 text-sm">
          <Switch checked={remember} onCheckedChange={setRemember} />
          记住我的选择
        </label>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            取消
          </Button>
          <Button variant="secondary" onClick={() => void choose("tray")}>
            最小化到托盘
          </Button>
          <Button variant="destructive" onClick={() => void choose("quit")}>
            直接退出
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
