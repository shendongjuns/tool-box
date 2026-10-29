import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * 输入框。高度与按钮默认尺寸一致（h-9），保证同一行内对齐。
 */
export const Input = React.forwardRef<
  HTMLInputElement,
  React.InputHTMLAttributes<HTMLInputElement>
>(({ className, type, ...props }, ref) => (
  <input
    type={type}
    ref={ref}
    className={cn(
      "flex h-9 w-full rounded-lg border border-input bg-[var(--card)] px-3 text-sm",
      "transition-colors placeholder:text-muted-foreground",
      "hover:border-border",
      "focus-visible:border-[var(--ring)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]/30",
      "disabled:cursor-not-allowed disabled:opacity-50",
      className,
    )}
    {...props}
  />
));
Input.displayName = "Input";
