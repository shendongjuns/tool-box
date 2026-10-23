import type { ReactNode } from "react";
import { ShieldCheck, Sparkles, Zap } from "lucide-react";
import { BrandLogo } from "@/components/brand-logo";

const highlights = [
  { icon: ShieldCheck, title: "私有部署", desc: "数据在自己的机器上" },
  { icon: Zap, title: "30 天免登录", desc: "会话自动续期" },
  { icon: Sparkles, title: "本地 / 云端", desc: "两套数据互不覆盖" },
];

/**
 * 登录/注册页布局。
 *
 * 整屏是一块连续背景（含两团柔和光晕），内容浮在同一层背景上，
 * 不做「左边一块、右边一块」的分区，因此中间没有任何色块接缝。
 *
 * 品牌字标固定在左上角，表单在右侧（窄屏居中）。
 */
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
    <div className="relative min-h-screen overflow-hidden bg-[var(--sidebar)]">
      {/* 全屏光晕：跨越整个页面，不按左右分区 */}
      <div
        aria-hidden
        className="pointer-events-none absolute -left-40 -top-40 h-[36rem] w-[36rem] rounded-full opacity-30 blur-3xl"
        style={{ background: "radial-gradient(circle, var(--primary), transparent 70%)" }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-48 right-0 h-[32rem] w-[32rem] rounded-full opacity-20 blur-3xl"
        style={{ background: "radial-gradient(circle, #22d3ee, transparent 70%)" }}
      />

      {/* 品牌字标：固定左上角 */}
      <header className="absolute left-6 top-6 z-10 sm:left-10 sm:top-8">
        <BrandLogo size="lg" showVersion />
      </header>

      {/* 内容层：左侧文案 + 右侧表单，共享同一背景 */}
      <div className="relative mx-auto grid min-h-screen w-full max-w-6xl items-center gap-12 px-6 py-24 lg:grid-cols-[1fr_auto] lg:gap-20 lg:px-10">
        {/* 品牌区：窄屏隐藏（字标已在左上角，这里只放文案） */}
        <aside className="hidden lg:flex lg:flex-col lg:justify-center">
          <h2 className="text-2xl font-semibold leading-snug tracking-tight">
            你的工具箱，
            <br />
            安静地放在自己的地方。
          </h2>

          <ul className="mt-8 space-y-3">
            {highlights.map(({ icon: Icon, title: itemTitle, desc }) => (
              <li key={itemTitle} className="flex items-center gap-2.5">
                <div className="grid h-7 w-7 shrink-0 place-items-center rounded-md border border-border/70 bg-card/60 backdrop-blur">
                  <Icon className="h-3.5 w-3.5 text-primary" />
                </div>
                <p className="text-sm font-medium">{itemTitle}</p>
                <p className="text-xs text-muted-foreground">{desc}</p>
              </li>
            ))}
          </ul>
        </aside>

        {/* 表单区：窄屏居中，宽屏右对齐 */}
        <main className="flex w-full justify-center lg:w-[26rem] lg:justify-end">
          <div className="w-full max-w-sm">
            {badge ? <div className="mb-6">{badge}</div> : null}

            <h1 className="text-xl font-semibold tracking-tight">{title}</h1>
            <p className="mt-1 text-sm text-muted-foreground">{description}</p>

            <div className="mt-6">{children}</div>

            <p className="mt-10 text-xs text-muted-foreground lg:hidden">
              © {new Date().getFullYear()} ToolBox
            </p>
          </div>
        </main>
      </div>
    </div>
  );
}
