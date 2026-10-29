import { z } from "zod";

const boolish = z
  .union([z.boolean(), z.string()])
  .transform((value) => (typeof value === "boolean" ? value : value === "true" || value === "1"));

/**
 * 服务端配置。
 *
 * 刻意**不包含**域名 / HTTPS / 证书相关配置：
 * 应用只负责在本机监听 HTTP，对外暴露方式（反向代理、隧道等）由部署者决定。
 */
const envSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  /*
   * 默认端口 7788。
   *
   * 原默认 3000，但 Windows 上 3000 常被 Hyper-V / WSL 划进
   * 「保留端口段」而无法绑定（EACCES），且保留段每次开机都会变 ——
   * 靠用户手动改端口不是长久之计。7788 远离常见段，实测稳定。
   */
  PORT: z.coerce.number().int().positive().default(7788),
  HOST: z.string().default("0.0.0.0"),
  DATABASE_PATH: z.string().default("./data/toolbox.db"),
  /** 会话有效期（天） */
  SESSION_TTL_DAYS: z.coerce.number().int().positive().default(30),
  /** 滑动续期的写库节流（分钟） */
  // 会话续期节流（分钟）：距上次使用超过该值才写库。
  // 5 分钟是「设备列表里最近使用」准确度与写频率的平衡点；
  // 30 天会话本身不需要更精确的时间戳。
  SESSION_RENEW_THROTTLE_MIN: z.coerce.number().int().nonnegative().default(5),
  /**
   * 是否信任 X-Forwarded-* 头。放在反向代理后面时保持默认 true，
   * 这样限流拿到的是真实客户端 IP，Cookie 也能识别出 HTTPS。
   */
  TRUST_PROXY: boolish.default(true),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  APP_VERSION: z.string().default("2.0.0"),
});

export type AppConfig = z.infer<typeof envSchema> & {
  sessionTtlMs: number;
  renewThrottleMs: number;
  isProduction: boolean;
  cookieName: string;
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
  };
}
