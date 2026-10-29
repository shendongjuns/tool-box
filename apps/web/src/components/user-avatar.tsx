import { cn } from "@/lib/utils";

/**
 * 用户头像。
 *
 * 目前所有账号都用同一张默认头像（`public/default_profile.png`）。
 * 将来支持上传头像时，只需在这里替换 src。
 */
export function UserAvatar({ size = 32, className }: { size?: number; className?: string }) {
  return (
    <img
      src="/default_profile.png"
      alt=""
      width={size}
      height={size}
      draggable={false}
      className={cn("shrink-0 rounded-full object-cover ring-1 ring-border/60", className)}
      style={{ width: size, height: size }}
    />
  );
}
