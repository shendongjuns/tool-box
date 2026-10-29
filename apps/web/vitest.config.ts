import { defineConfig } from "vitest/config";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  test: {
    // 纯逻辑模块用 node 环境即可，不引 jsdom（体积大且用不上）
    environment: "node",
    // zustand persist 会访问 localStorage；用 setup 文件提供最小桩，
    // 避免刷屏的 "storage is currently unavailable" 警告
    setupFiles: ["./src/test-setup.ts"],
    include: ["src/**/*.test.ts"],
  },
});
