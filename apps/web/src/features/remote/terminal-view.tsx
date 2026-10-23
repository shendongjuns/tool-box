import * as React from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import { sshResize, sshWrite } from "@/lib/ssh";

/**
 * xterm.js 终端视图。
 *
 * 输出由父组件通过 `termRef` 推送字节（已从 base64 解好），
 * 这里直接写 Uint8Array —— 让 xterm 处理 UTF-8 边界，避免多字节被切断。
 */
export interface TerminalHandle {
  write: (bytes: Uint8Array) => void;
  writeln: (text: string) => void;
  clear: () => void;
  focus: () => void;
}

export const TerminalView = React.forwardRef<
  TerminalHandle,
  {
    sessionId: string;
    className?: string;
  }
>(function TerminalView({ sessionId, className }, ref) {
  const containerRef = React.useRef<HTMLDivElement>(null);
  const termRef = React.useRef<Terminal | null>(null);

  React.useImperativeHandle(
    ref,
    () => ({
      write: (bytes) => termRef.current?.write(bytes),
      writeln: (text) => termRef.current?.writeln(text),
      clear: () => termRef.current?.clear(),
      focus: () => termRef.current?.focus(),
    }),
    [],
  );

  React.useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const term = new Terminal({
      fontFamily: 'ui-monospace, "Cascadia Code", "JetBrains Mono", Menlo, monospace',
      fontSize: 13,
      lineHeight: 1.4,
      cursorBlink: true,
      scrollback: 5000,
      theme: {
        background: "#0f1115",
        foreground: "#e4e6eb",
        cursor: "#8b8ff8",
        selectionBackground: "#3a3d4a",
        black: "#1a1c22",
        red: "#f07178",
        green: "#7fd88f",
        yellow: "#f5c56b",
        blue: "#82aaff",
        magenta: "#c792ea",
        cyan: "#89ddff",
        white: "#d8dbe3",
      },
    });

    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(container);
    // 首次 fit 需要在布局稳定后执行
    requestAnimationFrame(() => {
      try {
        fit.fit();
        void sshResize(sessionId, term.cols, term.rows);
      } catch {
        /* 忽略 */
      }
    });

    termRef.current = term;

    const inputSub = term.onData((input) => {
      const bytes = new TextEncoder().encode(input);
      let binary = "";
      for (const byte of bytes) binary += String.fromCharCode(byte);
      void sshWrite(sessionId, btoa(binary));
    });

    const observer = new ResizeObserver(() => {
      try {
        fit.fit();
        void sshResize(sessionId, term.cols, term.rows);
      } catch {
        /* 容器尺寸为 0 时 fit 会抛错 */
      }
    });
    observer.observe(container);

    return () => {
      observer.disconnect();
      inputSub.dispose();
      term.dispose();
      termRef.current = null;
    };
  }, [sessionId]);

  return <div ref={containerRef} className={className} />;
});
