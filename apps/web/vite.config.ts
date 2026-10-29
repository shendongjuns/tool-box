import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { tanstackRouter } from "@tanstack/router-plugin/vite";
import { fileURLToPath, URL } from "node:url";

const target = process.env.VITE_APP_TARGET === "desktop" ? "desktop" : "web";

/**
 * 后端地址。
 *
 * 默认 7788（与服务端一致）。开发时如果 7788 被占用，
 * 只要两边都设同一个 PORT 就能一起切换：
 *   PORT=8080 pnpm dev
 * 这里读同一个环境变量，避免「服务端换了端口但代理还指向旧端口」。
 */
const apiPort = process.env.PORT ?? "7788";
const apiTarget = `http://127.0.0.1:${apiPort}`;

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
    /*
     * 绑定 127.0.0.1 而不是默认的 localhost。
     *
     * Vite 默认解析 localhost 时在部分 Windows 上只听 [::1]（IPv6），
     * 导致 http://127.0.0.1:5173 连不上 —— 而很多工具/文档默认写 IPv4。
     * 显式指定 IPv4 后两种写法都能用。
     */
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    proxy: {
      // changeOrigin 必须为 false：服务端的 CSRF 校验比较 Origin 与 Host，
      // 改写 Host 会让两者不一致，所有写请求都会被 403 拒绝。
      "/api": { target: apiTarget, changeOrigin: false },
    },
  },
  build: {
    outDir: "dist",
    sourcemap: false,
    target: "es2022",
    /*
     * 抑制两类第三方噪声：
     * 1. zod 源码里的注释位置不符合 Rollup 的 annotation 规则
     *    （"contains an annotation that Rollup cannot interpret"）
     *    —— 这是 zod 4.6.7 自身写法问题，等上游修复
     * 2. rollup 的 chunk 划分建议
     */
    rollupOptions: {
      onwarn(warning, warn) {
        // zod 内部注释位置告警
        if (
          warning.code === "INVALID_ANNOTATION" ||
          (warning.message ?? "").includes("contains an annotation that Rollup cannot interpret")
        ) {
          return;
        }
        warn(warning);
      },
    },
  },
});
