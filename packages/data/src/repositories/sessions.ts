import { and, eq, gt, isNull, lt, ne } from "drizzle-orm";
import type { SessionKind } from "@toolbox/contracts";
import { sessions, type SessionRow } from "../schema.js";
import type { AppDatabase } from "../types.js";

export interface CreateSessionInput {
  id: string;
  userId: string;
  tokenHash: string;
  kind: SessionKind;
  deviceName: string | null;
  userAgent: string | null;
  ip: string | null;
  now: number;
  ttlMs: number;
}

export async function createSession(db: AppDatabase, input: CreateSessionInput): Promise<SessionRow> {
  await db.insert(sessions).values({
    id: input.id,
    userId: input.userId,
    tokenHash: input.tokenHash,
    kind: input.kind,
    deviceName: input.deviceName,
    userAgent: input.userAgent,
    ip: input.ip,
    createdAt: input.now,
    lastUsedAt: input.now,
    expiresAt: input.now + input.ttlMs,
    revokedAt: null,
  });
  const row = await findSessionByTokenHash(db, input.tokenHash);
  if (!row) throw new Error("session_create_failed");
  return row;
}

export async function findSessionByTokenHash(
  db: AppDatabase,
  tokenHash: string,
): Promise<SessionRow | undefined> {
  const rows = await db.select().from(sessions).where(eq(sessions.tokenHash, tokenHash)).limit(1);
  return rows[0];
}

/** 有效会话：未撤销且未过期。 */
export async function findActiveSessionByTokenHash(
  db: AppDatabase,
  tokenHash: string,
  now: number,
): Promise<SessionRow | undefined> {
  const rows = await db
    .select()
    .from(sessions)
    .where(
      and(
        eq(sessions.tokenHash, tokenHash),
        isNull(sessions.revokedAt),
        gt(sessions.expiresAt, now),
      ),
    )
    .limit(1);
  return rows[0];
}

export async function touchSession(
  db: AppDatabase,
  sessionId: string,
  now: number,
  ttlMs: number,
): Promise<void> {
  await db
    .update(sessions)
    .set({ lastUsedAt: now, expiresAt: now + ttlMs })
    .where(eq(sessions.id, sessionId));
}

export async function listSessions(db: AppDatabase, userId: string): Promise<SessionRow[]> {
  return db.select().from(sessions).where(eq(sessions.userId, userId));
}

export async function revokeSession(db: AppDatabase, sessionId: string, now: number): Promise<void> {
  await db.update(sessions).set({ revokedAt: now }).where(eq(sessions.id, sessionId));
}

export async function revokeUserSessions(
  db: AppDatabase,
  userId: string,
  now: number,
  exceptSessionId?: string,
): Promise<void> {
  const condition = exceptSessionId
    ? and(eq(sessions.userId, userId), ne(sessions.id, exceptSessionId))
    : eq(sessions.userId, userId);
  await db.update(sessions).set({ revokedAt: now }).where(condition);
}

/** 清理 N 天前就已过期的会话（避免表无限增长）。 */
export async function purgeExpiredSessions(
  db: AppDatabase,
  now: number,
  graceMs: number,
): Promise<number> {
  const rows = await db
    .delete(sessions)
    .where(lt(sessions.expiresAt, now - graceMs))
    .returning({ id: sessions.id });
  return rows.length;
}

export async function countActiveSessions(
  db: AppDatabase,
  userId: string,
  now: number,
): Promise<number> {
  const rows = await db
    .select({ id: sessions.id })
    .from(sessions)
    .where(and(eq(sessions.userId, userId), isNull(sessions.revokedAt), gt(sessions.expiresAt, now)));
  return rows.length;
}
