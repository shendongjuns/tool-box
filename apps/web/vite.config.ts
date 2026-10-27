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