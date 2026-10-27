import { buildApp } from "./app.js";

/**
 * 把监听失败翻译成可操作的提示。
 *
 * Windows 上最常见的两个坑：
 * - EACCES：端口落在系统保留区间（Hyper-V / WSL 会预留大量端口段），
 *   换一个端口即可，跟权限无关
 * - EADDRINUSE：端口已被占用
 */
function describeListenError(error: unknown, host: string, port: number): string {
  const code = (error as { code?: string } | null)?.code;

  if (code === "EACCES") {
    return [
      `无法监听 ${host}:${port}（EACCES）。`,
      "这个端口很可能被 Windows 保留段占用了（Hyper-V / WSL 会预留成片端口）。",
      "排查：netsh interface ipv4 show excludedportrange protocol=tcp",
      "解决：换一个不在保留段内的端口，例如 --port 8080。",
    ].join("\n");
  }

  if (code === "EADDRINUSE") {
    return [
      `端口 ${port} 已被占用（EADDRINUSE）。`,
      "解决：换端口，或先停掉占用该端口的进程。",
      "排查：netstat -ano | findstr :" + port,
    ].join("\n");
  }

  return `监听失败：${(error as Error)?.message ?? String(error)}`;
}

async function main(): Promise<void> {
  const { app } = await buildApp();
  const config = app.config;

  try {
    await app.listen({ port: config.PORT, host: config.HOST });
  } catch (error) {
    app.log.error(describeListenError(error, config.HOST, config.PORT));
    process.exit(1);
  }

  app.log.info(`ToolBox 已启动：http://${config.HOST}:${config.PORT}`);

  /*
   * 局域网访问提示。
   *
   * 绑定 0.0.0.0 时，用户通常想知道「别的设备该填什么地址」。
   * 这里把本机所有非回环 IPv4 打出来，省得他们去 ipconfig 里找。
   */
  if (config.HOST === "0.0.0.0") {
    void import("node:os").then(({ networkInterfaces }) => {
      /*
       * 过滤掉虚拟网卡。
       *
       * 28.0.0.1 是 VPN/隧道适配器，172.28.96.1 常是 WSL 或 Docker，
       * 把它们列出来只会让用户困惑（填了也连不上）。
       * 优先展示 192.168.x / 10.x / 172.16-31.x 这类真正的私网地址。
       */
      const isPrivateLan = (address: string): boolean => {
        if (address.startsWith("192.168.") || address.startsWith("10.")) return true;
        const match = /^172\.(\d+)\./.exec(address);
        if (match) {
          const second = Number(match[1]);
          return second >= 16 && second <= 31;
        }
        return false;
      };

      const candidates = Object.values(networkInterfaces())
        .flat()
        .filter((item) => item && item.family === "IPv4" && !item.internal)
        .map((item) => item!.address);

      /*
       * 私网地址优先；没有私网地址时退回展示全部。
       * 只保留第一张网卡 —— 多网卡环境（VPN / WSL / Docker）里
       * 罗列一堆地址反而让用户不知道填哪个。
       */
      const privateOnes = candidates.filter(isPrivateLan);
      const addresses = (privateOnes.length > 0 ? privateOnes : candidates).slice(0, 1);

      if (addresses.length === 0) {
        app.log.warn("未检测到局域网地址，其他设备可能无法访问");
        return;
      }

      app.log.info("局域网访问地址（在客户端「数据源」里填写）：");
      for (const address of addresses) {
        app.log.info(`  http://${address}:${config.PORT}`);
      }
    });
  }

  const shutdown = async (signal: string) => {
    app.log.info(`收到 ${signal}，正在关闭`);
    await app.close();
    process.exit(0);
  };
  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

void main();