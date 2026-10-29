/**
 * 迁移定义：服务端（better-sqlite3）与桌面端（rusqlite）共用。
 *
 * - 服务端在启动时按 idx 顺序执行未应用的迁移；
 * - 桌面端在首次打开本地库时用同一份 SQL 建表；
 * - SQL 只使用 SQLite 通用语法，避免方言差异。
 */
export interface Migration {
  idx: number;
  tag: string;
  sql: string;
}

export const migrations: Migration[] = [
  {
    idx: 0,
    tag: "0000_init",
    sql: `CREATE TABLE IF NOT EXISTS users (
  id text PRIMARY KEY NOT NULL,
  username text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  display_name text,
  created_at integer NOT NULL,
  updated_at integer NOT NULL,
  password_changed_at integer NOT NULL,
  last_login_at integer
);
CREATE TABLE IF NOT EXISTS sessions (
  id text PRIMARY KEY NOT NULL,
  user_id text NOT NULL,
  token_hash text NOT NULL UNIQUE,
  kind text NOT NULL,
  device_name text,
  user_agent text,
  ip text,
  created_at integer NOT NULL,
  last_used_at integer NOT NULL,
  expires_at integer NOT NULL,
  revoked_at integer,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE cascade
);
CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions (user_id);
CREATE INDEX IF NOT EXISTS sessions_expires_idx ON sessions (expires_at);
CREATE TABLE IF NOT EXISTS settings (
  key text PRIMARY KEY NOT NULL,
  value text NOT NULL,
  updated_at integer NOT NULL
);
CREATE TABLE IF NOT EXISTS tool_prefs (
  tool_id text PRIMARY KEY NOT NULL,
  pinned integer DEFAULT 0 NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  last_opened_at integer,
  updated_at integer NOT NULL
);`,
  },
  {
    idx: 1,
    tag: "0001_servers",
    sql: `CREATE TABLE IF NOT EXISTS servers (
  id text PRIMARY KEY NOT NULL,
  name text NOT NULL,
  host text NOT NULL,
  port integer DEFAULT 22 NOT NULL,
  username text NOT NULL,
  auth_type text NOT NULL,
  password_cipher text,
  private_key_cipher text,
  passphrase_cipher text,
  created_at integer NOT NULL,
  updated_at integer NOT NULL,
  last_connected_at integer
);`,
  },
];