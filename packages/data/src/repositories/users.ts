import { eq } from "drizzle-orm";
import { users, type UserRow } from "../schema.js";
import type { AppDatabase } from "../types.js";

export async function countUsers(db: AppDatabase): Promise<number> {
  const rows = await db.select({ id: users.id }).from(users);
  return rows.length;
}

/** 列出全部用户（单用户系统最多一条，用于初始化判断与登录页提示）。 */
export async function listUsers(db: AppDatabase): Promise<UserRow[]> {
  return db.select().from(users).limit(1);
}

export async function findUserByUsername(
  db: AppDatabase,
  username: string,
): Promise<UserRow | undefined> {
  const rows = await db.select().from(users).where(eq(users.username, username)).limit(1);
  return rows[0];
}

export async function findUserById(db: AppDatabase, id: string): Promise<UserRow | undefined> {
  const rows = await db.select().from(users).where(eq(users.id, id)).limit(1);
  return rows[0];
}

export interface CreateUserInput {
  id: string;
  username: string;
  passwordHash: string;
  displayName: string | null;
  now: number;
}

export async function createUser(db: AppDatabase, input: CreateUserInput): Promise<UserRow> {
  await db.insert(users).values({
    id: input.id,
    username: input.username,
    passwordHash: input.passwordHash,
    displayName: input.displayName,
    createdAt: input.now,
    updatedAt: input.now,
    passwordChangedAt: input.now,
    lastLoginAt: input.now,
  });
  const created = await findUserById(db, input.id);
  if (!created) throw new Error("user_create_failed");
  return created;
}

export async function updateUserPassword(
  db: AppDatabase,
  userId: string,
  passwordHash: string,
  now: number,
): Promise<void> {
  await db
    .update(users)
    .set({ passwordHash, passwordChangedAt: now, updatedAt: now })
    .where(eq(users.id, userId));
}

export async function updateLastLogin(db: AppDatabase, userId: string, now: number): Promise<void> {
  await db.update(users).set({ lastLoginAt: now, updatedAt: now }).where(eq(users.id, userId));
}