import * as React from "react";
import { useCallback, useMemo, useState } from "react";
import { Check, Copy, Minimize2, Sparkles, TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";

const SAMPLE = `{"name":"ToolBox","version":"2.0.0","features":["web","desktop"],"stable":true}`;

export function JsonFormatterTool() {
  /** 复制提示的复位定时器，卸载时必须清掉 */
  const copyTimer = React.useRef<number | null>(null);

  React.useEffect(() => {
    return () => {
      if (copyTimer.current) window.clearTimeout(copyTimer.current);
    };
  }, []);

  const [input, setInput] = useState(SAMPLE);
  const [indent, setIndent] = useState(2);
  const [copied, setCopied] = useState(false);

  const result = useMemo(() => {
    if (input.trim().length === 0) return { ok: true as const, output: "" };
    try {
      return { ok: true as const, output: JSON.stringify(JSON.parse(input), null, indent) };
    } catch (error) {
      return { ok: false as const, message: error instanceof Error ? error.message : "解析失败" };
    }
  }, [input, indent]);

  const minify = useCallback(() => {
    try {
      setInput(JSON.stringify(JSON.parse(input)));
    } catch {
      /* 非法输入保持原样 */
    }
  }, [input]);

  async function copy(value: string) {
    await navigator.clipboard.writeText(value);
    setCopied(true);
    toast.success("已复制");
    // 保存 timer 并在卸载时清理，避免组件已卸载还 setState
    if (copyTimer.current) window.clearTimeout(copyTimer.current);
    copyTimer.current = window.setTimeout(() => setCopied(false), 1500);
  }

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <CardTitle>JSON 格式化</CardTitle>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={minify}>
            <Minimize2 className="h-4 w-4" />
            压缩
          </Button>
          <Button variant="outline" size="sm" onClick={() => setInput(SAMPLE)}>
            <Sparkles className="h-4 w-4" />
            示例
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="input">
          <TabsList>
            <TabsTrigger value="input">输入</TabsTrigger>
            <TabsTrigger value="output">结果</TabsTrigger>
          </TabsList>

          <TabsContent value="input">
            <textarea
              value={input}
              onChange={(event) => setInput(event.target.value)}
              spellCheck={false}
              className="h-80 w-full resize-none rounded-lg border border-border bg-card p-3 font-mono text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]"
              placeholder="粘贴 JSON…"
            />
          </TabsContent>

          <TabsContent value="output">
            <div className="relative">
              <pre
                className={cn(
                  "h-80 overflow-auto rounded-lg border border-border bg-card p-3 font-mono text-sm",
                  !result.ok && "border-destructive/40",
                )}
              >
                {result.ok ? result.output || "（空）" : result.message}
              </pre>
              {result.ok && result.output ? (
                <Button
                  variant="secondary"
                  size="icon-sm"
                  className="absolute right-2 top-2"
                  onClick={() => void copy(result.output)}
                >
                  {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                </Button>
              ) : null}
            </div>
          </TabsContent>
        </Tabs>

        <div className="mt-4 flex items-center justify-between gap-3">
          <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
            {result.ok ? (
              <>
                <Check className="h-3.5 w-3.5 text-emerald-500" />
                合法 JSON
              </>
            ) : (
              <>
                <TriangleAlert className="h-3.5 w-3.5 text-destructive" />
                {result.message}
              </>
            )}
          </div>
          <label className="flex items-center gap-2 text-xs text-muted-foreground">
            缩进
            <select
              value={indent}
              onChange={(event) => setIndent(Number(event.target.value))}
              className="rounded-md border border-border bg-card px-2 py-1"
            >
              <option value={2}>2 空格</option>
              <option value={4}>4 空格</option>
              <option value={8}>8 空格</option>
            </select>
          </label>
        </div>
      </CardContent>
    </Card>
  );
}
