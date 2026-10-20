import { Database, Cloud } from "lucide-react";
import { useAuth } from "@/lib/auth-session";
import { useDataSource } from "@/lib/data-source";
import { canSwitchSource, DATA_SOURCES } from "@/lib/source";
import { cn } from "@/lib/utils";

/**
 * 数据源切换（仅桌面端可见）。
 *
 * 切换只改变「使用哪一套数据」，两套数据完全独立，互不覆盖。
 */
export function SourceSwitch({
  compact = false,
  onChanged,
}: {
  compact?: boolean;
  onChanged?: () => void;
}) {
  const { source, setSource } = useDataSource();
  const setAuth = useAuth((state) => state.setAuth);

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
            onClick={() => {
              if (active) return;
              setSource(id);
              setAuth(null);
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
