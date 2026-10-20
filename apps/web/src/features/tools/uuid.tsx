import { useState } from "react";
import { Copy, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";

function uuidV4(): string {
  return crypto.randomUUID();
}

export function UuidTool() {
  const [count, setCount] = useState(5);
  const [uppercase, setUppercase] = useState(false);
  const [list, setList] = useState<string[]>(() => Array.from({ length: 5 }, uuidV4));

  function regenerate() {
    setList(Array.from({ length: count }, uuidV4));
  }

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
            onChange={(event) => setCount(Number(event.target.value))}
            className="h-8 rounded-md border border-border bg-card px-2 text-xs"
          >
            {[1, 5, 10, 20, 50].map((value) => (
              <option key={value} value={value}>
                {value} 个
              </option>
            ))}
          </select>
          <Button variant="outline" size="sm" onClick={regenerate}>
            <RefreshCw className="h-4 w-4" />
            重新生成
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-1.5">
        {list.map((value, index) => {
          const display = uppercase ? value.toUpperCase() : value;
          return (
            <div
              key={`${value}-${index}`}
              className="flex items-center gap-2 rounded-md border border-border bg-muted/30 px-3 py-2"
            >
              <code className="min-w-0 flex-1 truncate font-mono text-sm">{display}</code>
              <Button variant="ghost" size="icon-sm" onClick={() => void navigator.clipboard.writeText(display)}>
                <Copy className="h-4 w-4" />
              </Button>
            </div>
          );
        })}
        <Button
          variant="secondary"
          className="w-full"
          onClick={() => void navigator.clipboard.writeText(list.map((value) => (uppercase ? value.toUpperCase() : value)).join("\n"))}
        >
          <Copy className="h-4 w-4" />
          复制全部
        </Button>
      </CardContent>
    </Card>
  );
}
