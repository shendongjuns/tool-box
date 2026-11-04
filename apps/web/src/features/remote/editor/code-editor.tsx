import * as React from "react";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import {
  bracketMatching,
  foldGutter,
  indentOnInput,
  syntaxHighlighting,
} from "@codemirror/language";
import { classHighlighter } from "@lezer/highlight";
import { cn } from "@/lib/utils";
import { detectLanguage } from "./language";

/**
 * 代码编辑器。
 *
 * 基于 CodeMirror 6 —— 比 Monaco 轻得多（约 150KB gzip），
 * 又比裸 textarea 多出行号、语法高亮、括号匹配、搜索。
 *
 * 三个外部约束：
 * - **受控但不重建**：value 变化时只 dispatch 替换事务，
 *   不销毁 EditorView，否则每次输入都会丢焦点。
 * - **只读模式**：部分文件允许查看但不许改（大文件、系统文件）。
 * - **主题跟随**：用 CSS 变量，深浅色由外层容器切换。
 */

interface CodeEditorProps {
  value: string;
  onChange?: (value: string) => void;
  /** 文件路径，用于推断语法高亮 */
  path: string;
  readOnly?: boolean;
  className?: string;
}

export function CodeEditor({ value, onChange, path, readOnly, className }: CodeEditorProps) {
  const containerRef = React.useRef<HTMLDivElement>(null);
  const viewRef = React.useRef<EditorView | null>(null);
  /** 避免「外部 value 变化 → dispatch → onChange → 再 setState」的死循环 */
  const applyingExternal = React.useRef(false);

  const onChangeRef = React.useRef(onChange);
  React.useEffect(() => {
    onChangeRef.current = onChange;
  }, [onChange]);

  React.useEffect(() => {
    const parent = containerRef.current;
    if (!parent) return;

    const extensions = [
      lineNumbers(),
      highlightActiveLine(),
      highlightSelectionMatches(),
      history(),
      bracketMatching(),
      foldGutter(),
      indentOnInput(),
      keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap, indentWithTab]),
      EditorView.lineWrapping,
      /*
       * 用 classHighlighter 而不是默认主题：
       * 具体颜色交给 CSS 变量，这样深浅色切换不用重建编辑器。
       */
      syntaxHighlighting(classHighlighter),
      detectLanguage(path) ?? [],
      EditorView.updateListener.of((update) => {
        if (!update.docChanged) return;
        if (applyingExternal.current) return;
        onChangeRef.current?.(update.state.doc.toString());
      }),
      EditorState.readOnly.of(Boolean(readOnly)),
      EditorView.editable.of(!readOnly),
    ];

    const view = new EditorView({
      state: EditorState.create({ doc: value, extensions }),
      parent,
    });
    viewRef.current = view;

    return () => {
      view.destroy();
      viewRef.current = null;
    };
    // 只在挂载时建一次；value 的变化走下面的同步逻辑
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path, readOnly]);

  // 外部 value 变化时同步进编辑器（不重建实例）
  React.useEffect(() => {
    const view = viewRef.current;
    if (!view) return;

    const current = view.state.doc.toString();
    if (current === value) return;

    applyingExternal.current = true;
    view.dispatch({
      changes: { from: 0, to: current.length, insert: value },
    });
    applyingExternal.current = false;
  }, [value]);

  return (
    <div
      ref={containerRef}
      className={cn(
        "min-h-0 flex-1 overflow-hidden rounded-md border border-border",
        // CodeMirror 的样式定制：字体、行高、主题色都走 CSS 变量
        "[&_.cm-editor]:h-full [&_.cm-editor]:outline-none",
        "[&_.cm-scroller]:font-mono [&_.cm-scroller]:text-[13px] [&_.cm-scroller]:leading-relaxed",
        "[&_.cm-gutters]:border-r [&_.cm-gutters]:border-border [&_.cm-gutters]:bg-muted/40",
        "[&_.cm-activeLine]:bg-accent/40 [&_.cm-activeLineGutter]:bg-accent/40",
        "[&_.cm-selectionMatch]:bg-primary/20",
        className,
      )}
    />
  );
}
