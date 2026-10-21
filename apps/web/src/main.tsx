import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { RouterProvider, createRouter } from "@tanstack/react-router";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "sonner";
import { routeTree } from "./routeTree.gen";
import { createQueryClient } from "./lib/query-client";
import { initTheme } from "./lib/theme";
import { useDataSource } from "./lib/data-source";
import { initDesktopBridge } from "./lib/desktop";
import "./styles/tokens.css";

const queryClient = createQueryClient();
const router = createRouter({
  routeTree,
  defaultPreload: "intent",
  context: { queryClient },
});

initTheme();
useDataSource.getState().load();

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}

async function bootstrap() {
  // 桌面端必须先拿到本地服务端口与已保存的令牌，再渲染，
  // 否则首个 /api/auth/me 会打在错误的地址上。
  await initDesktopBridge();

  const root = document.getElementById("root");
  if (!root) throw new Error("缺少 #root 挂载点");

  createRoot(root).render(
    <StrictMode>
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
        <Toaster
          position="bottom-right"
          richColors
          closeButton
          toastOptions={{ className: "font-sans" }}
        />
      </QueryClientProvider>
    </StrictMode>,
  );
}

void bootstrap();
