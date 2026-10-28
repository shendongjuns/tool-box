import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildApp, type BuiltApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";

/**
 * 服务器管理路由。
 *
 * 这是最复杂的新模块：CRUD + 凭据加密 + 一次性凭据下发。
 * 之前完全没有测试，而它直接关系到 SSH 密码的安全存储。
 */

let dir: string;
let built: BuiltApp;
let app: FastifyInstance;
let token: string;

const credentials = { username: "owner", password: "correct horse battery" };

const serverPayload = {
  name: "生产机",
  host: "192.168.1.10",
  port: 22,
  username: "root",
  authType: "password" as const,
  password: "super-secret-password",
};

beforeEach(async () => {
  dir = mkdtempSync(join(tmpdir(), "toolbox-servers-"));
  const config = loadConfig({
    NODE_ENV: "test",
    LOG_LEVEL: "silent",
    DATABASE_PATH: join(dir, "test.db"),
    SETUP_TOKEN: "",
    SESSION_RENEW_THROTTLE_MIN: "60",
  } as NodeJS.ProcessEnv);

  built = await buildApp({ config, databasePath: join(dir, "test.db") });
  app = built.app;

  // 建账号并拿桌面端令牌（Bearer 模式，绕过 Cookie）
  await app.inject({ method: "POST", url: "/api/auth/bootstrap", payload: credentials });
  const login = await app.inject({
    method: "POST",
    url: "/api/auth/desktop-login",
    payload: credentials,
  });
  token = JSON.parse(login.body).token as string;
});

afterEach(async () => {
  await app.close();
  built.db.close();
  rmSync(dir, { recursive: true, force: true });
});

/** 带令牌的请求。 */
function authed(method: "GET" | "POST" | "PUT" | "DELETE", url: string, payload?: unknown) {
  return app.inject({
    method,
    url,
    headers: { authorization: `Bearer ${token}` },
    ...(payload === undefined ? {} : { payload: payload as Record<string, unknown> }),
  });
}

describe("服务器 CRUD", () => {
  it("未认证访问返回 401", async () => {
    const response = await app.inject({ method: "GET", url: "/api/servers" });
    expect(response.statusCode).toBe(401);
  });

  it("创建后可查询，且不回传凭据内容", async () => {
    const created = await authed("POST", "/api/servers", serverPayload);
    expect(created.statusCode).toBe(201);

    const body = JSON.parse(created.body);
    expect(body.name).toBe("生产机");
    expect(body.hasCredential).toBe(true);
    // 关键：绝不能把密码回传给前端
    expect(created.body).not.toContain("super-secret-password");
    expect(body.password).toBeUndefined();
    expect(body.passwordCipher).toBeUndefined();

    const list = await authed("GET", "/api/servers");
    const items = JSON.parse(list.body).items;
    expect(items).toHaveLength(1);
    expect(items[0].id).toBe(body.id);
  });

  it("凭据在数据库中是密文，不是明文", async () => {
    await authed("POST", "/api/servers", serverPayload);

    const rows = built.db.raw.prepare("SELECT password_cipher FROM servers").all() as {
      password_cipher: string;
    }[];
    expect(rows).toHaveLength(1);

    const stored = rows[0]!.password_cipher;
    // 不能是明文
    expect(stored).not.toContain("super-secret-password");
    // 应该是 v1:iv:tag:data 格式（AES-256-GCM）
    expect(stored.startsWith("v1:")).toBe(true);
    // 三段十六进制
    const parts = stored.split(":");
    expect(parts).toHaveLength(4);
    expect(parts[1]).toMatch(/^[0-9a-f]{24}$/); // 12 字节 IV
    expect(parts[2]).toMatch(/^[0-9a-f]{32}$/); // 16 字节 tag
  });

  it("凭据接口能正确解密（往返一致）", async () => {
    const created = await authed("POST", "/api/servers", serverPayload);
    const id = JSON.parse(created.body).id as string;

    const credential = await authed("POST", `/api/servers/${id}/credential`);
    expect(credential.statusCode).toBe(200);

    const body = JSON.parse(credential.body);
    expect(body.password).toBe("super-secret-password");
    expect(body.host).toBe("192.168.1.10");
    expect(body.username).toBe("root");
  });

  it("同一密码两次加密结果不同（随机 IV）", async () => {
    await authed("POST", "/api/servers", { ...serverPayload, name: "A" });
    await authed("POST", "/api/servers", { ...serverPayload, name: "B" });

    const rows = built.db.raw.prepare("SELECT password_cipher FROM servers").all() as {
      password_cipher: string;
    }[];
    expect(rows).toHaveLength(2);
    expect(rows[0]!.password_cipher).not.toBe(rows[1]!.password_cipher);
  });

  it("更新时留空凭据表示不修改", async () => {
    const created = await authed("POST", "/api/servers", serverPayload);
    const id = JSON.parse(created.body).id as string;

    const updated = await authed("PUT", `/api/servers/${id}`, {
      name: "改名了",
      host: "192.168.1.10",
      port: 22,
      username: "root",
      authType: "password",
      // 不传 password
    });
    expect(updated.statusCode).toBe(200);
    expect(JSON.parse(updated.body).name).toBe("改名了");

    // 旧密码应该还在
    const credential = await authed("POST", `/api/servers/${id}/credential`);
    expect(JSON.parse(credential.body).password).toBe("super-secret-password");
  });

  it("删除后凭据接口返回 404", async () => {
    const created = await authed("POST", "/api/servers", serverPayload);
    const id = JSON.parse(created.body).id as string;

    const removed = await authed("DELETE", `/api/servers/${id}`);
    expect(removed.statusCode).toBe(204);

    const credential = await authed("POST", `/api/servers/${id}/credential`);
    expect(credential.statusCode).toBe(404);
  });

  it("不存在的服务器返回 404", async () => {
    expect((await authed("PUT", "/api/servers/nope", serverPayload)).statusCode).toBe(404);
    expect((await authed("DELETE", "/api/servers/nope")).statusCode).toBe(404);
    expect((await authed("POST", "/api/servers/nope/credential")).statusCode).toBe(404);
  });

  it("校验必填字段", async () => {
    const bad = await authed("POST", "/api/servers", {
      name: "",
      host: "1.2.3.4",
      port: 22,
      username: "root",
      authType: "password",
    });
    expect(bad.statusCode).toBe(400);
  });

  it("私钥模式的凭据也能往返", async () => {
    const created = await authed("POST", "/api/servers", {
      name: "密钥机",
      host: "10.0.0.5",
      port: 2222,
      username: "ubuntu",
      authType: "key",
      privateKey: "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----",
    });
    const id = JSON.parse(created.body).id as string;

    const credential = await authed("POST", `/api/servers/${id}/credential`);
    const body = JSON.parse(credential.body);
    expect(body.privateKey).toContain("BEGIN OPENSSH PRIVATE KEY");
    expect(body.password).toBeNull();
  });
});