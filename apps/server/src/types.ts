import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { AppDatabase } from "@toolbox/data";
import type { AppConfig } from "./config.js";
import type { AuthContext, AuthService } from "./auth/service.js";

declare module "fastify" {
  interface FastifyRequest {
    auth?: AuthContext;
  }
  interface FastifyInstance {
    config: AppConfig;
    db: AppDatabase;
    authService: AuthService;
    /**
     * 底层数据库句柄。
     *
     * 只在备份恢复时需要 —— 替换数据库文件前必须先关闭连接，
     * 否则 Windows 上文件被占用无法覆盖。
     */
    database: { readonly raw: unknown; close: () => void };
    /** 恢复完成后重新打开数据库（db 是 getter，会自动指向新连接） */
    reopenDatabase: () => void;
    /** 新建 authService 实例，绑定到重新打开的数据库 */
    reopenAuthService: () => void;
    /** 前置守卫：解析 Cookie/Bearer 令牌，失败直接 401 */
    requireAuth: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

// 让文件保持模块作用域（类型增强必须写在模块里）
export type _Augment = { request: FastifyRequest; reply: FastifyReply; instance: FastifyInstance };
