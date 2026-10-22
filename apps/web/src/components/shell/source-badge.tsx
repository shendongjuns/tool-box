import { Cloud, Database } from "lucide-react";
import { useDataSource } from "@/lib/data-source";
import { canSwitchSource } from "@/lib/source";
import { cn } from "@/lib/utils";

/** 数据源徽标：显示当前连接的名称（本地或用户命名的云端）。 */
export function SourceBadge({ className }: { className?: string }) {
  const { type, label } = useDataSource();
  if (!canSwitchSource()) return null;

  const Icon = type === "local" ? Database : Cloud;

  return (
    <span
      className={cn(
        "inline-flex max-w-[7rem] shrink-0 items-center gap-1 truncate rounded-full border border-border px-2 py-0.5 text-[11px] font-medium",
        type === "local"
          ? "text-emerald-600 dark:text-emerald-400"
          : "text-sky-600 dark:text-sky-400",
        className,
      )}
      title={label}
    >
      <Icon className="h-3 w-3 shrink-0" />
      <span className="truncate">{label}</span>
    </span>
  );
}
