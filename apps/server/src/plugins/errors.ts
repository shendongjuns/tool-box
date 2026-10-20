import type { FastifyInstance } from "fastify";
import { ZodError } from "zod";

export class ApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export const unauthorized = (message = "请先登录") => new ApiError(401, "UNAUTHENTICATED", message);
export const notFound = (message = "资源不存在") => new ApiError(404, "NOT_FOUND", message);
export const conflict = (code: string, message: string) => new ApiError(409, code, message);
export const badRequest = (code: string, message: string) => new ApiError(400, code, message);

/** 统一错误出口：所有异常都变成 { code, message, details? }。 */
export function registerErrorHandler(app: FastifyInstance): void {
  app.setErrorHandler((error: unknown, request, reply) => {
    if (error instanceof ApiError) {
      return reply.status(error.statusCode).send({
        code: error.code,
        message: error.message,
        ...(error.details === undefined ? {} : { details: error.details }),
      });
    }

    if (error instanceof ZodError) {
      return reply.status(400).send({
        code: "VALIDATION_FAILED",
        message: "请求参数不合法",
        details: error.issues.map((issue) => ({
          path: issue.path.join("."),
          message: issue.message,
        })),
      });
    }

    const statusCode = (error as { statusCode?: number }).statusCode ?? 500;
    if (statusCode >= 500) {
      request.log.error({ err: error }, "unhandled error");
      return reply.status(500).send({ code: "INTERNAL_ERROR", message: "服务器内部错误" });
    }
    return reply.status(statusCode).send({
      code: (error as { code?: string }).code ?? "REQUEST_FAILED",
      message: (error as { message?: string }).message ?? "请求失败",
    });
  });
}
