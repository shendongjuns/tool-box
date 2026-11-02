import type { FastifyInstance } from "fastify";
import { createReadStream, existsSync, statSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import {
  createBackup,
  deleteBackup,
  listBackups,
  restoreBackup,
  SCHEMA_VERSION,
  type BackupFile as BackupFileRow,
} from "@toolbox/data";
import {
  createBackupResponseSchema,
  deleteBackupResponseSchema,
  listBackupsResponseSchema,
  restoreBackupResponseSchema,
  type BackupFile,
} from "@toolbox/contracts";
import { badRequest, notFound } from "../plugins/errors.js";

/** 备份文件名白名单，与 @toolbox/data 内部的规则一致。 */
const NAME_RE = /^[\w.-]+\.v\d+-[\dT-]+(?:-\d+)?\.bak$/;

/** 转成对外 DTO：不暴露服务器上的绝对路径。 */
function toPublic(row: BackupFileRow): BackupFile {
  return {
    name: row.name,
    size: row.size,
    createdAt: row.createdAt,
    version: row.version,
  };
}

function assertName(name: string): void {
  if (!NAME_RE.test(name)) {
    throw badRequest("INVALID_BACKUP_NAME", "备份文件名不合法");
  }
}

/**
 * 数据库备份与恢复。
 *
 * 备份文件与数据库同目录。Docker 部署时该目录是挂载卷，
 * 所以备份天然落在宿主机上，重建容器不会丢。
 */
export async function registerBackupRoutes(app: FastifyInstance): Promise<void> {
  const dbPath = () => app.config.DATABASE_PATH;

  /** 列出全部备份。 */
  app.get("/api/backup", { preHandler: app.requireAuth }, async () => {
    const files = listBackups(dbPath());

    let databaseSize = 0;
    try {
      databaseSize = statSync(dbPath()).size;
    } catch {
      /* 库文件不存在时按 0 处理 */
    }

    return listBackupsResponseSchema.parse({
      files: files.map(toPublic),
      totalSize: files.reduce((sum, file) => sum + file.size, 0),
      databaseSize,
      schemaVersion: SCHEMA_VERSION,
    });
  });

  /** 立即创建一份手动备份。 */
  app.post("/api/backup", { preHandler: app.requireAuth }, async (_request, reply) => {
    const file = createBackup(dbPath(), SCHEMA_VERSION, "manual");
    void reply.code(201);
    return createBackupResponseSchema.parse({ file: toPublic(file) });
  });

  /** 下载某个备份文件。 */
  app.get<{ Params: { name: string } }>(
    "/api/backup/:name",
    { preHandler: app.requireAuth },
    async (request, reply) => {
      const { name } = request.params;
      assertName(name);

      const path = join(dirname(dbPath()), name);
      if (!existsSync(path)) {
        throw notFound("备份文件不存在");
      }

      /*
       * 流式响应，不读进内存：备份可能有几十上百 MB。
       */
      void reply
        .header("Content-Type", "application/octet-stream")
        .header("Content-Disposition", `attachment; filename="${encodeURIComponent(name)}"`)
        .header("Content-Length", statSync(path).size);

      return reply.send(createReadStream(path));
    },
  );

  /** 从某个备份恢复。 */
  app.post<{ Params: { name: string } }>(
    "/api/backup/:name/restore",
    { preHandler: app.requireAuth },
    async (request, reply) => {
      const { name } = request.params;
      assertName(name);

      const { reopenDatabase, reopenAuthService } = request.server;

      /*
       * 恢复必须关掉连接：Windows 上文件被占用时无法覆盖。
       *
       * 关键在于 close → reopen 之间**不能有任何 await**。
       * 这段窗口里若有并发请求访问数据库，会撞上已关闭的连接，
       * better-sqlite3 直接抛 "The database connection is not open"。
       * 所以顺序是：close → 同步替换文件 → 立刻 reopen，
       * 把窗口压到只有几条同步语句。
       */
      request.server.database.close();

      let safetyCopy = "";
      let failure: string | null = null;
      try {
        ({ safetyCopy } = restoreBackup(dbPath(), name, SCHEMA_VERSION));
      } catch (error) {
        failure = error instanceof Error ? error.message : "恢复失败";
      }

      // 无论成败都立刻重开，保证服务继续可用
      reopenDatabase();
      reopenAuthService();

      if (failure !== null) {
        throw badRequest("RESTORE_FAILED", failure);
      }

      /*
       * 恢复替换了整个数据库，sessions 表也在其中 ——
       * 当前令牌在新库里不存在，必须重新登录。
       */
      void reply.clearCookie(app.config.cookieName, { path: "/" });

      return restoreBackupResponseSchema.parse({
        ok: true,
        safetyCopy: basename(safetyCopy),
        requiresRelogin: true,
      });
    },
  );

  /** 删除某个备份。 */
  app.delete<{ Params: { name: string } }>(
    "/api/backup/:name",
    { preHandler: app.requireAuth },
    async (request) => {
      const { name } = request.params;
      assertName(name);

      try {
        deleteBackup(dbPath(), name);
      } catch (error) {
        throw notFound(error instanceof Error ? error.message : "删除失败");
      }

      return deleteBackupResponseSchema.parse({ ok: true });
    },
  );
}
