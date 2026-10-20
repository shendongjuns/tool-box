import { useEffect, useState } from "react";
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

  const numeric = Number(value);
  const timestamp = Number.isFinite(numeric) && value.trim() !== ""
    ? ms
      ? numeric
      : numeric * 1000
    : null;
  const date = timestamp !== null && timestamp > 0 ? new Date(timestamp) : null;
  const valid = date !== null && !Number.isNaN(date.getTime());

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
            <p className="mt-1 font-mono text-2xl font-semibold">
              {ms ? now : Math.floor(now / 1000)}
            </p>
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
            <p className={"mt-1 text-lg " + (valid ? "" : "text-destructive")}>
              {valid && date ? formatDateTime(date.getTime()) : "无效时间戳"}
            </p>
            {valid && date ? (
              <p className="mt-1 font-mono text-xs text-muted-foreground">
                {date.toISOString()}
              </p>
            ) : null}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
