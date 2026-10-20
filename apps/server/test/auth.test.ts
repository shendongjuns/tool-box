import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildApp, type BuiltApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";

let dir: string;
let built: BuiltApp;
let app: FastifyInstance;

beforeEach(async () => {
  dir = mkdtempSync(join(tmpdir(), "toolbox-test-"));
  const config = loadConfig({
    NODE_ENV: "test",
    LOG_LEVEL: "silent",
    DATABASE_PATH: join(dir, "test.db"),
    SETUP_TOKEN: "",
    SESSION_RENEW_THROTTLE_MIN: "60",
  } as NodeJS.ProcessEnv);
  built = await buildApp({ config, databasePath: join(dir, "test.db") });
  app = built.app;
});

afterEach(async () => {
  await app.close();
  built.db.close();
  rmSync(dir, { recursive: true, force: true });
});

const credentials = { username: "owner", password: "correct horse battery" };

async function bootstrap() {
  return app.inject({
    method: "POST",
    url: "/api/auth/bootstrap",
    payload: credentials,
  });
}

describe("首次注册", () => {
  it("空库时 initialized=false", async () => {
    const response = await app.inject({ method: "GET", url: "/api/auth/bootstrap" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ initialized: false });
  });

  it("注册成功后初始化状态变为 true，并下发 Cookie", async () => {
    const response = await bootstrap();
    expect(response.statusCode).toBe(201);
    const cookie = response.cookies.find((item) => item.name === "tb_session");
    expect(cookie).toBeDefined();
    expect(cookie?.httpOnly).toBe(true);

    const status = await app.inject({ method: "GET", url: "/api/auth/bootstrap" });
    expect(status.json()).toMatchObject({ initialized: true });
  });

  it("重复注册返回 409", async () => {
    expect((await bootstrap()).statusCode).toBe(201);
    const second = await bootstrap();
    expect(second.statusCode).toBe(409);
    expect(second.json().code).toBe("ALREADY_INITIALIZED");
  });
});

describe("登录与鉴权", () => {
  beforeEach(async () => {
    await bootstrap();
  });

  it("错误密码返回 401", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      payload: { username: credentials.username, password: "wrong password!" },
    });
    expect(response.statusCode).toBe(401);
  });

  it("正确密码返回用户信息与 30 天有效期", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      payload: credentials,
    });
    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.user.username).toBe(credentials.username);
    const ttl = body.session.expiresAt - Date.now();
    expect(ttl).toBeGreaterThan(29 * 24 * 60 * 60 * 1000);
  });

  it("未携带令牌访问受保护接口返回 401", async () => {
    const response = await app.inject({ method: "GET", url: "/api/auth/me" });
    expect(response.statusCode).toBe(401);
  });

  it("Bearer 令牌可访问受保护接口（桌面端路径）", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/auth/desktop-login",
      payload: { ...credentials, deviceName: "test-desktop" },
    });
    expect(login.statusCode).toBe(200);
    const { token } = login.json();
    expect(typeof token).toBe("string");

    const me = await app.inject({
      method: "GET",
      url: "/api/auth/me",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(me.statusCode).toBe(200);
    expect(me.json().user.username).toBe(credentials.username);
  });

  it("登出后令牌立即失效", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/auth/desktop-login",
      payload: credentials,
    });
    const token = login.json().token as string;

    const logout = await app.inject({
      method: "POST",
      url: "/api/auth/logout",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(logout.statusCode).toBe(204);

    const me = await app.inject({
      method: "GET",
      url: "/api/auth/me",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(me.statusCode).toBe(401);
  });

  it("改密后旧会话被撤销，新密码可登录", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/auth/desktop-login",
      payload: credentials,
    });
    const token = login.json().token as string;

    const other = await app.inject({
      method: "POST",
      url: "/api/auth/desktop-login",
      payload: { ...credentials, deviceName: "other" },
    });
    const otherToken = other.json().token as string;

    const changed = await app.inject({
      method: "POST",
      url: "/api/auth/password",
      headers: { authorization: `Bearer ${token}` },
      payload: {
        currentPassword: credentials.password,
        newPassword: "a brand new passphrase",
      },
    });
    expect(changed.statusCode).toBe(204);

    const otherMe = await app.inject({
      method: "GET",
      url: "/api/auth/me",
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(otherMe.statusCode).toBe(401);

    const relogin = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      payload: { username: credentials.username, password: "a brand new passphrase" },
    });
    expect(relogin.statusCode).toBe(200);
  });
});

describe("设置与工具", () => {
  let token: string;

  beforeEach(async () => {
    await bootstrap();
    const login = await app.inject({
      method: "POST",
      url: "/api/auth/desktop-login",
      payload: credentials,
    });
    token = login.json().token as string;
  });

  const auth = () => ({ authorization: `Bearer ${token}` });

  it("默认设置包含全部默认值", async () => {
    const response = await app.inject({ method: "GET", url: "/api/settings", headers: auth() });
    expect(response.statusCode).toBe(200);
    expect(response.json().values["ui.themeMode"]).toBe("system");
  });

  it("写入设置后读回一致", async () => {
    const put = await app.inject({
      method: "PUT",
      url: "/api/settings",
      headers: auth(),
      payload: { values: { "ui.themeMode": "dark", "ui.sidebarWidth": 280 } },
    });
    expect(put.statusCode).toBe(200);

    const get = await app.inject({ method: "GET", url: "/api/settings", headers: auth() });
    expect(get.json().values).toMatchObject({ "ui.themeMode": "dark", "ui.sidebarWidth": 280 });
  });

  it("工具清单来自内置目录", async () => {
    const response = await app.inject({ method: "GET", url: "/api/tools", headers: auth() });
    expect(response.statusCode).toBe(200);
    const items = response.json().items as { id: string }[];
    expect(items.length).toBeGreaterThan(3);
    expect(items.map((item) => item.id)).toContain("json-formatter");
  });

  it("置顶后排序优先", async () => {
    await app.inject({
      method: "PATCH",
      url: "/api/tools/uuid",
      headers: auth(),
      payload: { pinned: true },
    });
    const response = await app.inject({ method: "GET", url: "/api/tools", headers: auth() });
    const items = response.json().items as { id: string; pinned: boolean }[];
    expect(items[0]?.id).toBe("uuid");
    expect(items[0]?.pinned).toBe(true);
  });
});

describe("健康检查", () => {
  it("返回 ok 与版本号", async () => {
    const response = await app.inject({ method: "GET", url: "/api/health" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ status: "ok", db: "ok" });
  });
});
