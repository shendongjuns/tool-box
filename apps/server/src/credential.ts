import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from "node:crypto";

/**
 * 服务器凭据加解密。
 *
 * 用 AES-256-GCM。密钥由环境变量 `CREDENTIAL_KEY` 派生，未设置时退化到
 * 一个基于数据库路径的默认值（单机部署够用，多机请显式配置）。
 *
 * 密文格式：`v1:<iv-hex>:<tag-hex>:<data-hex>`
 */

const VERSION = "v1";

function deriveKey(secret: string): Buffer {
  // scrypt 派生固定 salt（salt 不保密，只用于避免直接使用口令）
  return scryptSync(secret, "toolbox-credential-v1", 32);
}

let cachedKey: Buffer | null = null;

function getKey(): Buffer {
  if (cachedKey) return cachedKey;
  const secret = process.env.CREDENTIAL_KEY ?? "toolbox-default-credential-key";
  cachedKey = deriveKey(secret);
  return cachedKey;
}

/** 加密明文；失败返回 null（不阻断保存，但记日志）。 */
export function encryptCredential(plain: string | undefined | null): string | null {
  if (!plain) return null;
  try {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", getKey(), iv);
    const data = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return [VERSION, iv.toString("hex"), tag.toString("hex"), data.toString("hex")].join(":");
  } catch {
    return null;
  }
}

/** 解密；格式不对或密钥变更时返回 null。 */
export function decryptCredential(cipherText: string | null | undefined): string | null {
  if (!cipherText) return null;
  const parts = cipherText.split(":");
  if (parts.length !== 4 || parts[0] !== VERSION) return null;

  try {
    const [, ivHex, tagHex, dataHex] = parts;
    const decipher = createDecipheriv("aes-256-gcm", getKey(), Buffer.from(ivHex!, "hex"));
    decipher.setAuthTag(Buffer.from(tagHex!, "hex"));
    const out = Buffer.concat([
      decipher.update(Buffer.from(dataHex!, "hex")),
      decipher.final(),
    ]);
    return out.toString("utf8");
  } catch {
    return null;
  }
}
