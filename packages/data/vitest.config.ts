import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // 桌面端与服务端都用 Node 运行时，测试里会直接读写文件与 SQLite
    environment: "node",
    include: ["test/**/*.test.ts"],
    // 备份文件名精确到秒，个别用例需要等一秒，放宽默认超时
    testTimeout: 20000,
  },
});
