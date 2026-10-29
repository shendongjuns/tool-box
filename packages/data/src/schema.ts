import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

/** 用户（每个数据源各自一份：本地库 / 云端库） */
export const users = sqliteTable("users", {
  id: text("id").primaryKey(),
  username: text("username").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  displayName: text("display_name"),
  createdAt: integer("created_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
  passwordChangedAt: integer("password_changed_at").notNull(),
  lastLoginAt: integer("last_login_at"),
});

/** 会话：库里只存 token 的 sha256，明文只在客户端 */
export const sessions = sqliteTable(
  "sessions",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    tokenHash: text("token_hash").notNull().unique(),
    kind: text("kind", { enum: ["web", "desktop", "local"] }).notNull(),
    deviceName: text("device_name"),
    userAgent: text("user_agent"),
    ip: text("ip"),
    createdAt: integer("created_at").notNull(),
    lastUsedAt: integer("last_used_at").notNull(),
    expiresAt: integer("expires_at").notNull(),
    revokedAt: integer("revoked_at"),
  },
  (t) => [
    index("sessions_user_idx").on(t.userId),
    index("sessions_expires_idx").on(t.expiresAt),
  ],
);

/** 键值设置（主题、侧栏宽度、关闭行为等） */
export const settings = sqliteTable("settings", {
  key: text("key").primaryKey(),
  value: text("value").notNull(),
  updatedAt: integer("updated_at").notNull(),
});

/** 工具偏好（置顶、排序、最近打开） */
export const toolPrefs = sqliteTable("tool_prefs", {
  toolId: text("tool_id").primaryKey(),
  pinned: integer("pinned", { mode: "boolean" }).notNull().default(false),
  sortOrder: integer("sort_order").notNull().default(0),
  lastOpenedAt: integer("last_opened_at"),
  updatedAt: integer("updated_at").notNull(),
});

/**
 * 远程服务器连接配置。
 *
 * 凭据（密码 / 私钥）不存明文：存储前用 AES-256-GCM 加密，
 * 密钥派生自机器标识 + 应用 salt（见 apps/desktop 的 crypto 模块）。
 * 云端数据源下这些字段由服务端保存，同样是密文。
 */
export const servers = sqliteTable("servers", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  host: text("host").notNull(),
  port: integer("port").notNull().default(22),
  username: text("username").notNull(),
  /** 认证方式：password 或 key */
  authType: text("auth_type", { enum: ["password", "key"] }).notNull(),
  /** 加密后的密码（authType=password） */
  passwordCipher: text("password_cipher"),
  /** 加密后的私钥（authType=key） */
  privateKeyCipher: text("private_key_cipher"),
  /** 私钥口令（可选，加密存储） */
  passphraseCipher: text("passphrase_cipher"),
  createdAt: integer("created_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
  lastConnectedAt: integer("last_connected_at"),
});

export type UserRow = typeof users.$inferSelect;
export type ServerRow = typeof servers.$inferSelect;
export type SessionRow = typeof sessions.$inferSelect;
export type SettingRow = typeof settings.$inferSelect;
export type ToolPrefRow = typeof toolPrefs.$inferSelect;