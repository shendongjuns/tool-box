export * as schema from "./schema.js";
export {
  createNodeDatabase,
  MigrationError,
  type NodeDatabase,
} from "./adapters/node.js";
export { migrations, SCHEMA_VERSION, type Migration } from "./migrations.js";
export {
  backupExists,
  createBackup,
  deleteBackup,
  exportBackup,
  listBackups,
  restoreBackup,
  type BackupFile,
} from "./backup.js";
export type { AppDatabase } from "./types.js";

export * from "./repositories/users.js";
export * from "./repositories/sessions.js";
export * from "./repositories/settings.js";
export * from "./repositories/tools.js";
export * from "./repositories/dashboard.js";
export * from "./repositories/servers.js";
export type { UserRow, SessionRow, SettingRow, ToolPrefRow, ServerRow } from "./schema.js";
