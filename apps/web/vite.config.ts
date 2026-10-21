import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { tanstackRouter } from "@tanstack/router-plugin/vite";
import { fileURLToPath, URL } from "node:url";

const target = process.env.VITE_APP_TARGET === "desktop" ? "desktop" : "web";

export default defineConfig({
  plugins: [
    tanstackRouter({
      target: "react",
      autoCodeSplitting: true,
      routesDirectory: "./src/routes",
      generatedRouteTree: "./src/routeTree.gen.ts",
    }),
    react(),
    tailwindcss(),
  ],
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  define: {
    __APP_TARGET__: JSON.stringify(target),
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      // changeOrigin 必须为 false：服务端的 CSRF 校验比较 Origin 与 Host，
      // 改写 Host 会让两者不一致，所有写请求都会被 403 拒绝。
      "/api": { target: "http://127.0.0.1:3000", changeOrigin: false },
    },
  },
  build: {
    outDir: "dist",
    sourcemap: false,
    target: "es2022",
  },
});
