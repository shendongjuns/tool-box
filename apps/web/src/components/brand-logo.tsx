import { cn } from "@/lib/utils";

/**
 * ToolBox 品牌字标。
 *
 * 纯文字的艺术化处理（无图标）：
 * - 双色渐变填充，跟随主题强调色
 * - 轻微倾斜 + 字距收紧，做出手写标记感
 * - 结尾的 "x" 用描边强调，像一枚小印章
 *
 * 用 CSS `background-clip: text` 实现，不含图片资源，
 * 深色/浅色与六套强调色都会自动适配。
 */
export function BrandLogo({
  size = "md",
  showVersion = false,
  className,
}: {
  size?: "sm" | "md" | "lg" | "xl";
  showVersion?: boolean;
  className?: string;
}) {
  const sizeClass = {
    sm: "text-base",
    md: "text-lg",
    lg: "text-2xl",
    xl: "text-4xl",
  }[size];

  return (
    <span className={cn("inline-flex items-baseline gap-1.5", className)}>
      <span
        className={cn(
          "brand-wordmark select-none font-extrabold leading-none tracking-[-0.03em]",
          sizeClass,
        )}
        aria-label="ToolBox"
      >
        Tool<span className="brand-box">Box</span>
      </span>
      {showVersion ? (
        <span className="rounded-full border border-border px-1.5 py-px text-[10px] font-medium tracking-normal text-muted-foreground">
          v2.0.0
        </span>
      ) : null}
    </span>
  );
}
