import type { ReactNode } from "react";
import { ShieldCheck, Sparkles, Zap } from "lucide-react";
import { BrandLogo } from "@/components/brand-logo";

const highlights = [
  { icon: ShieldCheck, title: "单用户私有部署", desc: "账号只属于你，数据放在自己的服务器或本机。" },
  { icon: Zap, title: "30 天免登录", desc: "会话自动续期，常用设备无需反复输入密码。" },
  { icon: Sparkles, title: "本地 / 云端双数据源", desc: "两套数据彼此独立，随时切换互不覆盖。" },
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
          <p className="mt-1.5 text-[10.5px] font-medium tracking-[0.2em] text-muted-foreground">
            YOUR PRIVATE TOOLKIT
          </p>
        </div>

        <div className="relative max-w-md">
          <h2 className="text-3xl font-semibold leading-tight tracking-tight">
            你的工具箱，
            <br />
            安静地放在自己的地方。
          </h2>
          <p className="mt-4 text-sm leading-relaxed text-muted-foreground">
            网页端与桌面端共享同一套体验：登录即用，离线也能开工，数据始终由你保管。
          </p>

          <ul className="mt-8 space-y-4">
            {highlights.map(({ icon: Icon, title: itemTitle, desc }) => (
              <li key={itemTitle} className="flex gap-3">
                <div className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-lg border border-border bg-card">
                  <Icon className="h-4 w-4 text-primary" />
                </div>
                <div>
                  <p className="text-sm font-medium">{itemTitle}</p>
                  <p className="text-xs text-muted-foreground">{desc}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <p className="relative text-xs text-muted-foreground">
          © {new Date().getFullYear()} ToolBox · React + Tauri + SQLite
        </p>
      </aside>

      {/* 右侧表单区 */}
      <main className="flex items-center justify-center px-5 py-10 sm:px-10">
        <div className="w-full max-w-sm">
          <div className="mb-8 flex items-center justify-between lg:hidden">
            <BrandLogo size="md" />
          </div>

          {badge ? <div className="mb-6">{badge}</div> : null}

          <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
          <p className="mt-1.5 text-sm text-muted-foreground">{description}</p>

          <div className="mt-7">{children}</div>
        </div>
      </main>
    </div>
  );
}