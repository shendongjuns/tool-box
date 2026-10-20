import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";

/** 32 字节随机令牌，base64url 编码（43 字符）。 */
export function generateToken(): string {
  return randomBytes(32).toString("base64url");
}

/** 令牌在库里只以 sha256 形式存在。 */
export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** 定长比较，避免时序侧信道。 */
export function safeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

export function newId(): string {
  return randomUUID();
}
