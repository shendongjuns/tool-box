import { z } from "zod";

const boolish = z
  .union([z.boolean(), z.string()])
  .transform((value) => (typeof value === "boolean" ? value : value === "true" || value === "1"));

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default("0.0.0.0"),
  DATABASE_PATH: z.string().default("./data/toolbox.db"),
  PUBLIC_ORIGIN: z.string().default("http://localhost:5173"),
  SESSION_TTL_DAYS: z.coerce.number().int().positive().default(30),
  SESSION_RENEW_THROTTLE_MIN: z.coerce.number().int().nonnegative().default(60),
  COOKIE_SECURE: boolish.default(false),
  TRUST_PROXY: boolish.default(false),
  SETUP_TOKEN: z.string().default(""),
  BACKUP_KEEP: z.coerce.number().int().nonnegative().default(7),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  APP_VERSION: z.string().default("2.0.0"),
});

export type AppConfig = z.infer<typeof envSchema> & {
  sessionTtlMs: number;
  renewThrottleMs: number;
  isProduction: boolean;
  cookieName: string;
  /** 便于路由层短写 */
  setupToken: string;
  cookieSecure: boolean;
  publicOrigin: string;
  backupKeep: number;
};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = envSchema.safeParse(env);
  if (!parsed.success) {
    const detail = parsed.error.issues
      .map((issue) => `${issue.path.join(".") || "(root)"}: ${issue.message}`)
      .join("; ");
    throw new Error(`配置校验失败: ${detail}`);
  }
  const value = parsed.data;
  return {
    ...value,
    sessionTtlMs: value.SESSION_TTL_DAYS * 24 * 60 * 60 * 1000,
    renewThrottleMs: value.SESSION_RENEW_THROTTLE_MIN * 60 * 1000,
    isProduction: value.NODE_ENV === "production",
    cookieName: "tb_session",
    setupToken: value.SETUP_TOKEN,
    cookieSecure: value.COOKIE_SECURE,
    publicOrigin: value.PUBLIC_ORIGIN,
    backupKeep: value.BACKUP_KEEP,
  };
}
