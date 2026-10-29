import { asc, eq } from "drizzle-orm";
import { servers, type ServerRow } from "../schema.js";
import type { AppDatabase } from "../types.js";

export interface CreateServerInput {
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  authType: "password" | "key";
  passwordCipher: string | null;
  privateKeyCipher: string | null;
  passphraseCipher: string | null;
  now: number;
}

/** 服务器列表（按名称排序）。 */
export async function listServers(db: AppDatabase): Promise<ServerRow[]> {
  return db.select().from(servers).orderBy(asc(servers.name));
}

export async function findServer(db: AppDatabase, id: string): Promise<ServerRow | undefined> {
  const rows = await db.select().from(servers).where(eq(servers.id, id)).limit(1);
  return rows[0];
}

export async function createServer(
  db: AppDatabase,
  input: CreateServerInput,
): Promise<ServerRow> {
  await db.insert(servers).values({
    id: input.id,
    name: input.name,
    host: input.host,
    port: input.port,
    username: input.username,
    authType: input.authType,
    passwordCipher: input.passwordCipher,
    privateKeyCipher: input.privateKeyCipher,
    passphraseCipher: input.passphraseCipher,
    createdAt: input.now,
    updatedAt: input.now,
    lastConnectedAt: null,
  });
  const row = await findServer(db, input.id);
  if (!row) throw new Error("server_create_failed");
  return row;
}

export async function updateServer(
  db: AppDatabase,
  id: string,
  patch: Partial<Omit<CreateServerInput, "id" | "now">>,
  now: number,
): Promise<boolean> {
  const existing = await findServer(db, id);
  if (!existing) return false;

  await db
    .update(servers)
    .set({
      name: patch.name ?? existing.name,
      host: patch.host ?? existing.host,
      port: patch.port ?? existing.port,
      username: patch.username ?? existing.username,
      authType: patch.authType ?? existing.authType,
      // 只有显式传入才覆盖凭据字段（undefined 表示不改）
      ...(patch.passwordCipher === undefined
        ? {}
        : { passwordCipher: patch.passwordCipher }),
      ...(patch.privateKeyCipher === undefined
        ? {}
        : { privateKeyCipher: patch.privateKeyCipher }),
      ...(patch.passphraseCipher === undefined
        ? {}
        : { passphraseCipher: patch.passphraseCipher }),
      updatedAt: now,
    })
    .where(eq(servers.id, id));
  return true;
}

export async function deleteServer(db: AppDatabase, id: string): Promise<boolean> {
  const existing = await findServer(db, id);
  if (!existing) return false;
  await db.delete(servers).where(eq(servers.id, id));
  return true;
}

export async function touchServerConnection(
  db: AppDatabase,
  id: string,
  now: number,
): Promise<void> {
  await db.update(servers).set({ lastConnectedAt: now }).where(eq(servers.id, id));
}
