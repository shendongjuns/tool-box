import { useEffect, useMemo, useState } from "react";
import { Copy } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { formatDateTime } from "@/lib/utils";

export function TimestampTool() {
  const [now, setNow] = useState(() => Date.now());
  const [ms, setMs] = useState(true);
  const [value, setValue] = useState(() => String(Date.now()));

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  const parsed = useMemo(() => {
    const trimmed = value.trim();
    if (trimmed === "") return { date: null, valid: false };
    const numeric = Number(trimmed);
    if (!Number.isFinite(numeric) || numeric <= 0) return { date: null, valid: false };
    const date = new Date(ms ? numeric : numeric * 1000);
    return { date, valid: !Number.isNaN(date.getTime()) };
  }, [value, ms]);

  const current = ms ? now : Math.floor(now / 1000);

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle>当前时间</CardTitle>
          <Button
            variant="outline"
            size="sm"
            onClick={() => setValue(String(ms ? Date.now() : Math.floor(Date.now() / 1000)))}
          >
            填入当前
          </Button>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <p className="text-xs text-muted-foreground">Unix 时间戳（{ms ? "毫秒" : "秒"}）</p>
            <div className="mt-1 flex items-center gap-2">
              <span className="font-mono text-2xl font-semibold">{current}</span>
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={async () => {
                  await navigator.clipboard.writeText(String(current));
                  toast.success("已复制");
                }}
              >
                <Copy className="h-4 w-4" />
              </Button>
            </div>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">本地时间</p>
            <p className="mt-1 text-lg">{formatDateTime(now)}</p>
          </div>
          <div className="flex items-center justify-between rounded-lg border border-border px-3 py-2">
            <span className="text-sm">使用毫秒</span>
            <Switch checked={ms} onCheckedChange={setMs} />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>时间戳转换</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Field>
            <FieldLabel htmlFor="ts">时间戳</FieldLabel>
            <Input
              id="ts"
              value={value}
              onChange={(event) => setValue(event.target.value)}
              className="font-mono"
            />
          </Field>
          <div className="rounded-lg border border-border bg-muted/40 p-4">
            <p className="text-xs text-muted-foreground">转换结果</p>
            <p className={`mt-1 text-lg ${parsed.valid ? "" : "text-destructive"}`}>
              {parsed.valid && parsed.date ? formatDateTime(parsed.date.getTime()) : "无效时间戳"}
            </p>
            {parsed.valid && parsed.date ? (
              <p className="mt-1 font-mono text-xs text-muted-foreground">
                {parsed.date.toISOString()}
              </p>
            ) : null}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
