import type { ReactNode } from "react";
import { ShieldCheck, Sparkles, Zap } from "lucide-react";
import { BrandLogo } from "@/components/brand-logo";

const highlights = [
  { icon: ShieldCheck, title: "私有部署", desc: "数据放在自己的机器上" },
  { icon: Zap, title: "30 天免登录", desc: "会话自动续期" },
  { icon: Sparkles, title: "本地 / 云端", desc: "两套数据互不覆盖" },
];

export function AuthLayout({
  title,
  description,
  badge,
  children,
}: {
  title: string;
  description: string;
  badge?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="grid min-h-screen lg:grid-cols-[1.05fr_1fr]">
      {/* 左侧品牌区（桌面宽度下显示） */}
      <aside className="relative hidden overflow-hidden bg-[var(--sidebar)] lg:flex lg:flex-col lg:justify-between lg:p-12">
        <div
          aria-hidden
          className="pointer-events-none absolute -left-24 -top-24 h-[28rem] w-[28rem] rounded-full opacity-40 blur-3xl"
          style={{ background: "radial-gradient(circle, var(--primary), transparent 70%)" }}
        />
        <div
          aria-hidden
          className="pointer-events-none absolute -bottom-32 right-0 h-[24rem] w-[24rem] rounded-full opacity-25 blur-3xl"
          style={{ background: "radial-gradient(circle, #22d3ee, transparent 70%)" }}
        />

        <div className="relative">
          <BrandLogo size="lg" showVersion />
        </div>

        <div className="relative max-w-sm">
          <h2 className="text-2xl font-semibold leading-snug tracking-tight">
            你的工具箱，
            <br />
            安静地放在自己的地方。
          </h2>

          <ul className="mt-7 space-y-3">
            {highlights.map(({ icon: Icon, title: itemTitle, desc }) => (
              <li key={itemTitle} className="flex items-center gap-2.5">
                <div className="grid h-7 w-7 shrink-0 place-items-center rounded-md border border-border bg-card">
                  <Icon className="h-3.5 w-3.5 text-primary" />
                </div>
                <p className="text-sm font-medium">{itemTitle}</p>
                <p className="text-xs text-muted-foreground">{desc}</p>
              </li>
            ))}
          </ul>
        </div>

        <p className="relative text-xs text-muted-foreground">
          © {new Date().getFullYear()} ToolBox
        </p>
      </aside>

      {/* 右侧表单区 */}
      {/* 右侧表单区：背景与左侧品牌区保持一致，避免中间出现色块分界 */}
      <main className="flex items-center justify-center bg-[var(--sidebar)] px-5 py-10 sm:px-10">
        <div className="w-full max-w-sm">
          <div className="mb-8 flex items-center justify-between lg:hidden">
            <BrandLogo size="md" />
          </div>

          {badge ? <div className="mb-6">{badge}</div> : null}

          <h1 className="text-xl font-semibold tracking-tight">{title}</h1>
          <p className="mt-1 text-sm text-muted-foreground">{description}</p>

          <div className="mt-6">{children}</div>
        </div>
      </main>
    </div>
  );
}