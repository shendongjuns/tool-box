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
    /** 前置守卫：解析 Cookie/Bearer 令牌，失败直接 401 */
    requireAuth: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

// 让文件保持模块作用域（类型增强必须写在模块里）
export type _Augment = { request: FastifyRequest; reply: FastifyReply; instance: FastifyInstance };
