import type { BaseSQLiteDatabase } from "drizzle-orm/sqlite-core";
import type * as schema from "./schema.js";

/**
 * 应用数据库句柄。
 *
 * 服务端是 better-sqlite3（同步驱动），桌面端是 sqlite-proxy（异步驱动），
 * 两者都继承自 BaseSQLiteDatabase，因此 repository 层只需要面向这一个类型。
 * 所有 repository 方法声明为 async —— 同步驱动的返回值会被 await 直接展开。
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type AppDatabase = BaseSQLiteDatabase<"sync" | "async", any, typeof schema>;
