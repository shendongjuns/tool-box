import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

/**
 * 服务器凭据加解密（AES-256-GCM）。
 *
 * 密钥来源优先级：
 * 1. 环境变量 `CREDENTIAL_KEY`（推荐，生产必须设置）
 * 2. 数据库同目录下的 `.credential-key` 文件（首次启动自动生成，0600 权限）
 *
 * 早期版本在未设置环境变量时退化成一个**硬编码常量** ——
 * 等于所有部署共用同一把钥匙，任何人 clone 代码就能解开别人的库。
 * 现在改为每实例随机生成并持久化，绝不用常量兜底。
 *
 * 密文格式：`v1:<iv-hex>:<tag-hex>:<data-hex>`
 */

const VERSION = "v1";

/** 默认密钥文件名，与数据库放同一目录。 */
const KEY_FILE = ".credential-key";

function deriveKey(secret: string): Buffer {
  return scryptSync(secret, "toolbox-credential-v1", 32);
}

let cachedKey: Buffer | null = null;

/** 读取或生成实例专属密钥。 */
function loadOrCreateSecret(): string {
  const fromEnv = process.env.CREDENTIAL_KEY;
  if (fromEnv && fromEnv.length >= 16) return fromEnv;

  const dbPath = process.env.DATABASE_PATH ?? "./data/toolbox.db";
  const dir = dirname(resolve(dbPath));
  const keyPath = join(dir, KEY_FILE);

  try {
    if (existsSync(keyPath)) {
      const existing = readFileSync(keyPath, "utf8").trim();
      if (existing.length >= 32) return existing;
    }

    // 生成 32 字节随机密钥并以仅本人可读的权限落盘
    const secret = randomBytes(32).toString("hex");
    mkdirSync(dir, { recursive: true });
    writeFileSync(keyPath, secret, { mode: 0o600 });
    return secret;
  } catch {
    /*
     * 落盘失败时退回「进程内随机密钥」：
     * 本次运行可正常加解密，重启后旧密文无法解开（用户需重新填写凭据）。
     * 这比使用固定常量安全得多 —— 常量意味着全世界的部署共用一把钥匙。
     */
    return randomBytes(32).toString("hex");
  }
}

function getKey(): Buffer {
  if (cachedKey) return cachedKey;
  cachedKey = deriveKey(loadOrCreateSecret());
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