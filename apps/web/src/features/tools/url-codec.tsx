import { useState } from "react";
import { ArrowDownUp, Copy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export function UrlCodecTool() {
  const [input, setInput] = useState("https://example.com/search?q=工具 箱");
  const [mode, setMode] = useState<"encode" | "decode">("encode");

  const output = (() => {
    try {
      return mode === "encode" ? encodeURIComponent(input) : decodeURIComponent(input);
    } catch {
      return "（无法解码：输入包含非法转义序列）";
    }
  })();

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <CardTitle>URL 编解码</CardTitle>
        <Button variant="outline" size="sm" onClick={() => setMode(mode === "encode" ? "decode" : "encode")}>
          <ArrowDownUp className="h-4 w-4" />
          当前：{mode === "encode" ? "编码" : "解码"}
        </Button>
      </CardHeader>
      <CardContent className="space-y-3">
        <textarea
          value={input}
          onChange={(event) => setInput(event.target.value)}
          spellCheck={false}
          className="h-40 w-full resize-none rounded-lg border border-border bg-card p-3 font-mono text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]"
        />
        <div className="relative">
          <pre className="max-h-56 overflow-auto rounded-lg border border-border bg-muted/40 p-3 font-mono text-sm break-all whitespace-pre-wrap">
            {output || "（空）"}
          </pre>
          <Button
            variant="secondary"
            size="icon-sm"
            className="absolute right-2 top-2"
            onClick={() => void navigator.clipboard.writeText(output)}
          >
            <Copy className="h-4 w-4" />
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
