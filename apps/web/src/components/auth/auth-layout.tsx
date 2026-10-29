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
 * 整屏一块连续背景（含两团柔和光晕），内容浮在其上。
 * 左上角是品牌字标；下方左栏是标语与特性，右栏是表单。
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
      {/* 全屏光晕 */}
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

      {/* 左上角品牌字标 */}
      <header className="absolute left-6 top-6 z-10 sm:left-10 sm:top-8">
        <BrandLogo size="lg" showVersion />
      </header>

      <div className="relative mx-auto flex min-h-screen w-full max-w-6xl flex-col px-6 sm:px-10">
        {/*
          主内容：垂直居中的两栏。
          左栏用固定宽度承载标语，右栏表单固定 22rem，两者基线对齐。
        */}
        <div className="flex flex-1 items-center">
          <div className="grid w-full items-center gap-16 lg:grid-cols-[minmax(0,1fr)_22rem]">
            {/* 左栏：标语 + 特性 */}
            <aside className="hidden lg:block">
              <h1 className="text-[2rem] font-semibold leading-[1.25] tracking-tight text-balance">
                你的工具箱，
                <br />
                安静地放在自己的地方。
              </h1>

              <div className="mt-10 space-y-4 border-l border-border/60 pl-5">
                {highlights.map(({ icon: Icon, title: itemTitle, desc }) => (
                  <div key={itemTitle} className="flex items-start gap-2.5">
                    <Icon className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary/80" />
                    <p className="text-sm leading-snug">
                      <span className="font-medium">{itemTitle}</span>
                      <span className="text-muted-foreground"> · {desc}</span>
                    </p>
                  </div>
                ))}
              </div>
            </aside>

            {/* 右栏：表单 */}
            <main className="flex justify-center lg:justify-end">
              <div className="w-full max-w-sm">
                {badge ? <div className="mb-6">{badge}</div> : null}

                <h2 className="text-xl font-semibold tracking-tight">{title}</h2>
                <p className="mt-1 text-sm text-muted-foreground">{description}</p>

                <div className="mt-6">{children}</div>

                <p className="mt-10 text-xs text-muted-foreground lg:hidden">
                  © {new Date().getFullYear()} ToolBox
                </p>
              </div>
            </main>
          </div>
        </div>

        {/* 页脚：仅在宽屏显示，与左栏对齐 */}
        <footer className="hidden pb-8 lg:block">
          <p className="text-xs text-muted-foreground">© {new Date().getFullYear()} ToolBox</p>
        </footer>
      </div>
    </div>
  );
}
