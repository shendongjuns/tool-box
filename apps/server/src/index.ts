import { buildApp } from "./app.js";

async function main(): Promise<void> {
  const { app } = await buildApp();
  const config = app.config;

  try {
    await app.listen({ port: config.PORT, host: config.HOST });
    app.log.info(`ToolBox server listening on http://${config.HOST}:${config.PORT}`);
  } catch (error) {
    app.log.error(error);
    process.exit(1);
  }

  const shutdown = async (signal: string) => {
    app.log.info(`received ${signal}, shutting down`);
    await app.close();
    process.exit(0);
  };
  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

void main();
