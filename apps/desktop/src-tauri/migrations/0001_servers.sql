CREATE TABLE IF NOT EXISTS servers (
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
);
