import { useMemo, useState } from "react";
import { ArrowDownUp, Copy } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";

function encode(value: string, urlSafe: boolean): string {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const base = btoa(binary);
  return urlSafe ? base.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "") : base;
}

function decode(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/").replace(/\s/g, "");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

export function Base64Tool() {
  const [input, setInput] = useState("ToolBox 2.0");
  const [mode, setMode] = useState<"encode" | "decode">("encode");
  const [urlSafe, setUrlSafe] = useState(false);

  /**
   * 结果只在 useMemo 里算，绝不在渲染期间 setState ——
   * 那会触发 "Too many re-renders" 死循环。
   */
  const result = useMemo<{ output: string; error: string | null }>(() => {
    if (input.length === 0) return { output: "", error: null };
    try {
      return {
        output: mode === "encode" ? encode(input, urlSafe) : decode(input),
        error: null,
      };
    } catch {
      return { output: "", error: "无法解码：输入不是合法的 Base64" };
    }
  }, [input, mode, urlSafe]);

  async function copy() {
    if (!result.output) return;
    await navigator.clipboard.writeText(result.output);
    toast.success("已复制");
  }

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <CardTitle>Base64 编解码</CardTitle>
        <div className="flex items-center gap-3 text-xs text-muted-foreground">
          <span>URL 安全</span>
          <Switch checked={urlSafe} onCheckedChange={setUrlSafe} />
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="grid gap-3 lg:grid-cols-2">
          <div>
            <label className="mb-1.5 block text-xs font-medium text-muted-foreground">
              {mode === "encode" ? "原文" : "Base64"}
            </label>
            <textarea
              value={input}
              onChange={(event) => setInput(event.target.value)}
              spellCheck={false}
              className="h-56 w-full resize-none rounded-lg border border-border bg-card p-3 font-mono text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]"
            />
          </div>
          <div>
            <div className="mb-1.5 flex items-center justify-between">
              <label className="text-xs font-medium text-muted-foreground">
                {mode === "encode" ? "Base64" : "原文"}
              </label>
              <Button variant="ghost" size="icon-sm" onClick={() => void copy()}>
                <Copy className="h-4 w-4" />
              </Button>
            </div>
            <pre className="h-56 overflow-auto whitespace-pre-wrap break-all rounded-lg border border-border bg-muted/40 p-3 font-mono text-sm">
              {result.error ?? (result.output || "（空）")}
            </pre>
          </div>
        </div>

        <Button
          variant="outline"
          size="sm"
          onClick={() => setMode(mode === "encode" ? "decode" : "encode")}
        >
          <ArrowDownUp className="h-4 w-4" />
          切换为{mode === "encode" ? "解码" : "编码"}
        </Button>
      </CardContent>
    </Card>
  );
}
