import * as React from "react";
import { AlertTriangle, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * 错误边界。
 *
 * 之前任何组件抛异常都会让整个应用白屏 ——
 * 桌面端用户没有浏览器的「刷新」按钮，只能强杀进程。
 * 现在至少给出一条可操作的出路：重载界面 / 复制错误详情。
 */

interface State {
  error: Error | null;
  info: string;
}

export class ErrorBoundary extends React.Component<{ children: React.ReactNode }, State> {
  state: State = { error: null, info: "" };

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo): void {
    // 控制台留档，同时写进 state 供「复制详情」使用
    console.error("界面渲染出错", error, info.componentStack);
    this.setState({ info: info.componentStack ?? "" });
  }

  private reload = (): void => {
    window.location.reload();
  };

  private copyDetail = (): void => {
    const { error, info } = this.state;
    const text = [error?.stack ?? String(error), info].filter(Boolean).join("\n\n");
    void navigator.clipboard?.writeText(text);
  };

  render(): React.ReactNode {
    const { error, info } = this.state;
    if (!error) return this.props.children;

    return (
      <div className="grid min-h-screen place-items-center bg-background p-6">
        <div className="w-full max-w-lg rounded-xl border border-border bg-card p-6">
          <div className="flex items-center gap-2.5">
            <AlertTriangle className="h-5 w-5 text-destructive" />
            <h1 className="text-base font-semibold">界面出错了</h1>
          </div>

          <p className="mt-2 text-sm text-muted-foreground">
            某个组件渲染时抛出了异常。你的数据没有丢失， 点击「重载界面」通常就能恢复。
          </p>

          <pre className="mt-3 max-h-40 overflow-auto rounded-md bg-muted/60 p-3 font-mono text-[11px] text-muted-foreground">
            {error.message}
            {info ? `\n${info.slice(0, 600)}` : ""}
          </pre>

          <div className="mt-4 flex gap-2">
            <Button size="sm" onClick={this.reload}>
              <RotateCcw className="h-3.5 w-3.5" />
              重载界面
            </Button>
            <Button size="sm" variant="ghost" onClick={this.copyDetail}>
              复制错误详情
            </Button>
          </div>
        </div>
      </div>
    );
  }
}
