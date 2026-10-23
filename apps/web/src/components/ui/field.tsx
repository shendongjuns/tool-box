import * as React from "react";
import { cn } from "@/lib/utils";

/** 表单字段容器：标签 + 控件 + 提示，纵向紧凑排列。 */
export function Field({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex flex-col gap-1.5", className)} {...props} />;
}

export function FieldLabel({ className, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) {
  return <label className={cn("text-xs font-medium text-foreground", className)} {...props} />;
}

export function FieldHint({ className, ...props }: React.HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn("text-xs leading-relaxed text-muted-foreground", className)} {...props} />;
}

export function FieldError({ className, ...props }: React.HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn("text-xs text-destructive", className)} {...props} />;
}
