import {
  countUsers,
  createUser,
  createSession,
  findActiveSessionByTokenHash,
  findUserById,
  findUserByUsername,
  listUsers,
  touchSession,
  updateLastLogin,
  updateUserPassword,
  type AppDatabase,
} from "@toolbox/data";
import type { UserRow } from "@toolbox/data/schema";
import type { PublicUser, SessionKind } from "@toolbox/contracts";
import type { AppConfig } from "../config.js";
import { generateToken, hashToken, newId } from "./tokens.js";

export interface IssuedSession {
  token: string;
  sessionId: string;
  expiresAt: number;
}

export interface AuthContext {
  user: UserRow;
  sessionId: string;
  expiresAt: number;
  kind: SessionKind;
}

export interface LoginMeta {
  kind: SessionKind;
  deviceName: string | null;
  userAgent: string | null;
  ip: string | null;
}

export function toPublicUser(row: UserRow): PublicUser {
  return {
    id: row.id,
    username: row.username,
    displayName: row.displayName,
    createdAt: row.createdAt,
    lastLoginAt: row.lastLoginAt,
  };
}

export class AuthService {
  constructor(
    private readonly db: AppDatabase,
    private readonly config: AppConfig,
  ) {}

  /** 库里是否已经有用户（单用户系统里最多一个）。 */
  async isInitialized(): Promise<boolean> {
    return (await countUsers(this.db)) > 0;
  }

  /** 已注册的账号（用于登录页提示用户名）。 */
  async findOwner(): Promise<UserRow | undefined> {
    return this.firstUser();
  }

  private async firstUser(): Promise<UserRow | undefined> {
    const rows = await listUsers(this.db);
    return rows[0];
  }

  /** 创建会话：令牌明文返回给调用方，库里只留 sha256。 */
  async issueSession(userId: string, meta: LoginMeta, now = Date.now()): Promise<IssuedSession> {
    const token = generateToken();
    const row = await createSession(this.db, {
      id: newId(),
      userId,
      tokenHash: hashToken(token),
      kind: meta.kind,
      deviceName: meta.deviceName,
      userAgent: meta.userAgent,
      ip: meta.ip,
      now,
      ttlMs: this.config.sessionTtlMs,
    });
    return { token, sessionId: row.id, expiresAt: row.expiresAt };
  }

  /** 只在 users 为空时调用（路由层已做检查，这里再做一次兜底）。 */
  async createFirstUser(input: {
    username: string;
    passwordHash: string;
    displayName: string | null;
    now?: number;
  }): Promise<UserRow> {
    return createUser(this.db, {
      id: newId(),
      username: input.username,
      passwordHash: input.passwordHash,
      displayName: input.displayName,
      now: input.now ?? Date.now(),
    });
  }

  async findByUsername(username: string): Promise<UserRow | undefined> {
    return findUserByUsername(this.db, username);
  }

  async markLogin(userId: string, now = Date.now()): Promise<void> {
    await updateLastLogin(this.db, userId, now);
  }

  async changePassword(userId: string, passwordHash: string, now = Date.now()): Promise<void> {
    await updateUserPassword(this.db, userId, passwordHash, now);
  }

  /**
   * 校验令牌并（必要时）滑动续期。
   *
   * 续期节流：距上次使用不足阈值就不写库，避免每个请求都产生一次写事务。
   */
  async authenticate(token: string, now = Date.now()): Promise<AuthContext | null> {
    const session = await findActiveSessionByTokenHash(this.db, hashToken(token), now);
    if (!session) return null;

    if (now - session.lastUsedAt >= this.config.renewThrottleMs) {
      await touchSession(this.db, session.id, now, this.config.sessionTtlMs);
    }

    const user = await findUserById(this.db, session.userId);
    if (!user) return null;

    return { user, sessionId: session.id, expiresAt: session.expiresAt, kind: session.kind };
  }
}