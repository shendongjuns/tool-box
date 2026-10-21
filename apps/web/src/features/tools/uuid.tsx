import { useState } from "react";
import { Copy, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";

/** 优先用 crypto.randomUUID，非安全上下文（http 局域网访问）退化为 getRandomValues。 */
function uuidV4(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function UuidTool() {
  const [count, setCount] = useState(5);
  const [uppercase, setUppercase] = useState(false);
  const [list, setList] = useState<string[]>(() => Array.from({ length: 5 }, uuidV4));

  const regenerate = (nextCount = count) => {
    setList(Array.from({ length: nextCount }, uuidV4));
  };

  const display = (value: string) => (uppercase ? value.toUpperCase() : value);

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <CardTitle>UUID 生成器</CardTitle>
        <div className="flex items-center gap-3">
          <label className="flex items-center gap-2 text-xs text-muted-foreground">
            大写
            <Switch checked={uppercase} onCheckedChange={setUppercase} />
          </label>
          <select
            value={count}
            onChange={(event) => {
              const next = Number(event.target.value);
              setCount(next);
              regenerate(next);
            }}
            className="h-8 rounded-md border border-border bg-card px-2 text-xs"
          >
            {[1, 5, 10, 20, 50].map((value) => (
              <option key={value} value={value}>
                {value} 个
              </option>
            ))}
          </select>
          <Button variant="outline" size="sm" onClick={() => regenerate()}>
            <RefreshCw className="h-4 w-4" />
            重新生成
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-1.5">
        {list.map((value, index) => (
          <div
            key={`${value}-${index}`}
            className="flex items-center gap-2 rounded-md border border-border bg-muted/30 px-3 py-2"
          >
            <code className="min-w-0 flex-1 truncate font-mono text-sm">{display(value)}</code>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={async () => {
                await navigator.clipboard.writeText(display(value));
                toast.success("已复制");
              }}
            >
              <Copy className="h-4 w-4" />
            </Button>
          </div>
        ))}
        <Button
          variant="secondary"
          className="w-full"
          onClick={async () => {
            await navigator.clipboard.writeText(list.map(display).join("\n"));
            toast.success(`已复制 ${list.length} 条`);
          }}
        >
          <Copy className="h-4 w-4" />
          复制全部
        </Button>
      </CardContent>
    </Card>
  );
}
