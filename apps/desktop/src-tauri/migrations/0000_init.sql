CREATE TABLE IF NOT EXISTS `users` (
  `id` text PRIMARY KEY NOT NULL,
  `username` text NOT NULL UNIQUE,
  `password_hash` text NOT NULL,
  `display_name` text,
  `created_at` integer NOT NULL,
  `updated_at` integer NOT NULL,
  `password_changed_at` integer NOT NULL,
  `last_login_at` integer
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `sessions` (
  `id` text PRIMARY KEY NOT NULL,
  `user_id` text NOT NULL,
  `token_hash` text NOT NULL UNIQUE,
  `kind` text NOT NULL,
  `device_name` text,
  `user_agent` text,
  `ip` text,
  `created_at` integer NOT NULL,
  `last_used_at` integer NOT NULL,
  `expires_at` integer NOT NULL,
  `revoked_at` integer,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `sessions_user_idx` ON `sessions` (`user_id`);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `sessions_expires_idx` ON `sessions` (`expires_at`);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `settings` (
  `key` text PRIMARY KEY NOT NULL,
  `value` text NOT NULL,
  `updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `tool_prefs` (
  `tool_id` text PRIMARY KEY NOT NULL,
  `pinned` integer DEFAULT false NOT NULL,
  `sort_order` integer DEFAULT 0 NOT NULL,
  `last_opened_at` integer,
  `updated_at` integer NOT NULL
);