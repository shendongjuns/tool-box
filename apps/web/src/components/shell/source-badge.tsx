import { Cloud, Database } from "lucide-react";
import { useDataSource } from "@/lib/data-source";
import { canSwitchSource, DATA_SOURCES } from "@/lib/source";
import { cn } from "@/lib/utils";

/** 数据源徽标：桌面端常驻，提示当前用的是哪套数据。 */
export function SourceBadge({ className }: { className?: string }) {
  const source = useDataSource((state) => state.source);
  if (!canSwitchSource()) return null;

  const info = DATA_SOURCES[source];
  const Icon = source === "local" ? Database : Cloud;

  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center gap-1 rounded-full border border-border px-2 py-0.5 text-[11px] font-medium",
        source === "local"
          ? "text-emerald-600 dark:text-emerald-400"
          : "text-sky-600 dark:text-sky-400",
        className,
      )}
      title={info.description}
    >
      <Icon className="h-3 w-3" />
      {info.short}
    </span>
  );
}
