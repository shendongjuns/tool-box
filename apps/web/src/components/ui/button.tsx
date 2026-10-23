import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

/**
 * 按钮。
 *
 * 尺寸规范（与 Input 对齐）：
 * - sm  h-8  小号，用于行内操作
 * - md  h-9  默认，与输入框同高
 * - lg  h-10 强调操作
 * 圆角统一 rounded-lg，仅 icon 变体用同一半径保证正方形。
 */
const buttonVariants = cva(
  [
    "inline-flex items-center justify-center gap-1.5 whitespace-nowrap rounded-lg text-sm font-medium",
    "transition-colors outline-none select-none",
    "disabled:pointer-events-none disabled:opacity-50",
    "focus-visible:ring-2 focus-visible:ring-[var(--ring)]/40 focus-visible:border-[var(--ring)]",
    "[&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  ].join(" "),
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:opacity-90 active:opacity-100",
        secondary: "bg-secondary text-secondary-foreground hover:bg-accent hover:text-accent-foreground",
        outline: "border border-border bg-transparent hover:bg-accent hover:text-accent-foreground",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        destructive: "bg-destructive text-destructive-foreground hover:opacity-90",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-9 px-3.5",
        sm: "h-8 px-2.5 text-xs",
        lg: "h-10 px-5",
        icon: "h-9 w-9",
        "icon-sm": "h-8 w-8",
      },
    },
    defaultVariants: { variant: "default", size: "default" },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />;
  },
);
Button.displayName = "Button";

export { buttonVariants };
