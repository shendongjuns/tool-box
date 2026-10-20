import { useState } from "react";
import { ArrowDownUp, Copy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";

function encode(value: string, urlSafe: boolean): string {
  const base = btoa(String.fromCharCode(...new TextEncoder().encode(value)));
  return urlSafe ? base.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "") : base;
}

function decode(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  return new TextDecoder().decode(Uint8Array.from(binary, (char) => char.charCodeAt(0)));
}

export function Base64Tool() {
  const [input, setInput] = useState("ToolBox 2.0");
  const [mode, setMode] = useState<"encode" | "decode">("encode");
  const [urlSafe, setUrlSafe] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const output = (() => {
    if (input.length === 0) return "";
    try {
      setError(null);
      return mode === "encode" ? encode(input, urlSafe) : decode(input);
    } catch {
      return "（无法解码：输入不是合法的 Base64）";
    }
  })();

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
              <Button variant="ghost" size="icon-sm" onClick={() => void navigator.clipboard.writeText(output)}>
                <Copy className="h-4 w-4" />
              </Button>
            </div>
            <pre className="h-56 overflow-auto rounded-lg border border-border bg-muted/40 p-3 font-mono text-sm">
              {output || "（空）"}
            </pre>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setMode(mode === "encode" ? "decode" : "encode")}
          >
            <ArrowDownUp className="h-4 w-4" />
            切换为{mode === "encode" ? "解码" : "编码"}
          </Button>
          {error ? <span className="text-xs text-destructive">{error}</span> : null}
        </div>
      </CardContent>
    </Card>
  );
}
