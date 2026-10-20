import { hash, verify } from "@node-rs/argon2";

/**
 * Argon2id 参数（OWASP 推荐档）。
 * 参数写进哈希串本身，未来调参不会让旧密码失效。
 */
const ARGON_OPTIONS = {
  algorithm: 2, // Algorithm.Argon2id（用数字避免 ambient enum 限制）
  memoryCost: 19456,
  timeCost: 2,
  parallelism: 1,
} as const;

export function hashPassword(password: string): Promise<string> {
  return hash(password, ARGON_OPTIONS);
}

export async function verifyPassword(passwordHash: string, password: string): Promise<boolean> {
  try {
    return await verify(passwordHash, password, ARGON_OPTIONS);
  } catch {
    return false;
  }
}
