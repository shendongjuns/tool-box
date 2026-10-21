import { useMemo, useState } from "react";
import { ArrowDownUp, Copy } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export function UrlCodecTool() {
  const [input, setInput] = useState("https://example.com/search?q=工具箱");
  const [mode, setMode] = useState<"encode" | "decode">("encode");

  const result = useMemo(() => {
    try {
      return {
        output: mode === "encode" ? encodeURIComponent(input) : decodeURIComponent(input),
        error: null as string | null,
      };
    } catch {
      return { output: "", error: "无法解码：输入包含非法转义序列" };
    }
  }, [input, mode]);

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <CardTitle>URL 编解码</CardTitle>
        <Button
          variant="outline"
          size="sm"
          onClick={() => setMode(mode === "encode" ? "decode" : "encode")}
        >
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
          <pre className="max-h-56 overflow-auto whitespace-pre-wrap break-all rounded-lg border border-border bg-muted/40 p-3 font-mono text-sm">
            {result.error ?? (result.output || "（空）")}
          </pre>
          <Button
            variant="secondary"
            size="icon-sm"
            className="absolute right-2 top-2"
            onClick={async () => {
              await navigator.clipboard.writeText(result.output);
              toast.success("已复制");
            }}
          >
            <Copy className="h-4 w-4" />
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
