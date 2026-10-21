import { Cloud, Database } from "lucide-react";
import { useDataSource } from "@/lib/data-source";
import { switchDataSource } from "@/lib/session";
import { canSwitchSource, DATA_SOURCES } from "@/lib/source";
import { cn } from "@/lib/utils";

/**
 * 数据源切换（仅桌面端可见）。
 *
 * 切换只改变「使用哪一套数据」，两套数据完全独立，互不覆盖。
 * 切换后清空登录态与 Query 缓存，避免把旧数据源的数据带过去。
 */
export function SourceSwitch({
  compact = false,
  onChanged,
}: {
  compact?: boolean;
  onChanged?: () => void;
}) {
  const source = useDataSource((state) => state.source);

  if (!canSwitchSource()) return null;

  return (
    <div
      className={cn(
        "inline-flex items-center gap-1 rounded-lg border border-border bg-muted/50 p-1",
        compact ? "text-xs" : "text-sm",
      )}
      role="group"
      aria-label="数据源"
    >
      {(["local", "cloud"] as const).map((id) => {
        const active = source === id;
        const Icon = id === "local" ? Database : Cloud;
        return (
          <button
            key={id}
            type="button"
            aria-pressed={active}
            onClick={async () => {
              if (active) return;
              await switchDataSource(id);
              onChanged?.();
            }}
            className={cn(
              "inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 font-medium transition-colors",
              active
                ? "bg-card text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground",
            )}
            title={DATA_SOURCES[id].description}
          >
            <Icon className="h-3.5 w-3.5" />
            {DATA_SOURCES[id].short}
          </button>
        );
      })}
    </div>
  );
}
