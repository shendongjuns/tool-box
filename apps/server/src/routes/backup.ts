import type { FastifyInstance } from "fastify";
import {
  createReadStream,
  existsSync,
  mkdtempSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import {
  createBackup,
  deleteBackup,
  importBackup,
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
import { badRequest, conflict, notFound } from "../plugins/errors.js";

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
  const dbPath = () => app.databasePath;

  /*
   * 恢复操作的互斥锁。
   *
   * 恢复会关闭数据库连接、替换文件、再重开。这段窗口里
   * 如果有第二个恢复请求进来，两个流程会交叉操作同一个文件，
   * 结果是数据库被写坏 —— 而这恰恰是用户最需要数据安全的时刻。
   *
   * 用布尔锁挡住并发，第二个请求直接收到 409。
   */
  let restoring = false;

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

      if (restoring) {
        throw conflict("RESTORE_IN_PROGRESS", "已有恢复操作正在进行，请稍候");
      }
      restoring = true;

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
      restoring = false;

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

  /**
   * 导入外部备份文件。
   *
   * 请求体是原始字节（不是 JSON），所以这里用 addContentTypeParser
   * 单独给这个路由注册 octet-stream 解析。
   *
   * 文件名通过 X-Backup-Name 头传递 —— 因为 body 已经被文件内容占用，
   * 没有地方放元数据。这个头只用于提取版本号与时间戳，
   * 实际落盘的文件名会按本机库名重写，所以不担心路径穿越。
   */
  /*
   * 给这个路由单独注册二进制解析。
   *
   * Fastify 默认只解析 JSON，文件上传需要自己接管
   * application/octet-stream。用 addContentTypeParser 而不是
   * 全局改 bodyLimit，避免影响其它接口。
   */
  app.addContentTypeParser(
    "application/octet-stream",
    /*
     * 上限 32MB。
     *
     * 之前设了 512MB，但 parseAs: "buffer" 会把**整个文件读进内存** ——
     * 一次导入就能吃掉 512MB，几个并发直接 OOM。
     *
     * 32MB 对单用户的工具箱足够（正常库也就几 MB），
     * 同时把内存风险压到可接受范围。
     * 真要导入更大的库，用户可以直接把文件拷进 data 目录。
     */
    { parseAs: "buffer", bodyLimit: 32 * 1024 * 1024 },
    (_request, body, done) => done(null, body),
  );

  app.post("/api/backup/import", { preHandler: app.requireAuth }, async (request) => {
    const content = request.body as Buffer;
    if (!Buffer.isBuffer(content) || content.length === 0) {
      throw badRequest("EMPTY_FILE", "文件是空的");
    }

    /*
     * 先落到临时文件，再交给 importBackup 校验。
     * 直接信任内存里的字节会更简单，但 importBackup 需要走
     * 与磁盘备份完全相同的校验路径（SQLite 魔数检查）。
     */
    const tempDir = mkdtempSync(join(tmpdir(), "toolbox-import-"));
    const headerName = String(request.headers["x-backup-name"] ?? "imported.bak");
    // 只用 basename，防止头里塞路径
    const safeName = basename(headerName).replace(/[^\w.-]/g, "_") || "imported.bak";
    const tempPath = join(tempDir, safeName);

    try {
      writeFileSync(tempPath, content);
      const file = importBackup(dbPath(), tempPath, SCHEMA_VERSION);
      return createBackupResponseSchema.parse({ file: toPublic(file) });
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

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
