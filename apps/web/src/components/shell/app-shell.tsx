import * as React from "react";
import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";
import { CommandPalette } from "./command-palette";
import { useThemeSync } from "@/lib/theme-sync";
import { cn } from "@/lib/utils";

/**
 * 应用壳层：侧栏 + 顶栏 + 内容区。
 *
 * 桌面端在顶部留出拖拽区（-webkit-app-region），网页端无影响。
 */
export function AppShell({ children }: { children: React.ReactNode }) {
  const [collapsed, setCollapsed] = React.useState(false);
  const [commandOpen, setCommandOpen] = React.useState(false);
  useThemeSync();

  React.useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setCommandOpen((open) => !open);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      <Sidebar collapsed={collapsed} onToggle={() => setCollapsed((value) => !value)} />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar onOpenCommand={() => setCommandOpen(true)} />
        <main
          className={cn(
            "min-h-0 flex-1 overflow-y-auto",
            "bg-[radial-gradient(circle_at_100%_0%,color-mix(in_oklch,var(--primary)_7%,transparent),transparent_45%)]",
          )}
        >
          <div className="mx-auto w-full max-w-6xl px-6 py-7">{children}</div>
        </main>
      </div>
      <CommandPalette open={commandOpen} onOpenChange={setCommandOpen} />
    </div>
  );
}
