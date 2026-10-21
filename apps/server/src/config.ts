import { z } from "zod";

const boolish = z
  .union([z.boolean(), z.string()])
  .transform((value) => (typeof value === "boolean" ? value : value === "true" || value === "1"));

/**
 * 服务端配置。
 *
 * 刻意**不包含**域名 / HTTPS / 反向代理相关的必填项：
 * 这些由部署侧的 nginx 负责，应用只监听 HTTP。
 */
const envSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default("0.0.0.0"),
  DATABASE_PATH: z.string().default("./data/toolbox.db"),
  /** 会话有效期（天） */
  SESSION_TTL_DAYS: z.coerce.number().int().positive().default(30),
  /** 滑动续期的写库节流（分钟） */
  SESSION_RENEW_THROTTLE_MIN: z.coerce.number().int().nonnegative().default(60),
  /**
   * 是否信任 X-Forwarded-* 头。放在 nginx 后面时保持默认 true，
   * 这样限流拿到的是真实客户端 IP，Cookie 也能识别出 HTTPS。
   */
  TRUST_PROXY: boolish.default(true),
  /** 一次性注册口令，留空表示不校验 */
  SETUP_TOKEN: z.string().default(""),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  APP_VERSION: z.string().default("2.0.0"),
});

export type AppConfig = z.infer<typeof envSchema> & {
  sessionTtlMs: number;
  renewThrottleMs: number;
  isProduction: boolean;
  cookieName: string;
  setupToken: string;
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
  };
}
