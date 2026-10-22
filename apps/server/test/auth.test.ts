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
  it("空库时 initialized=false 且没有用户名", async () => {
    const response = await app.inject({ method: "GET", url: "/api/auth/bootstrap" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ initialized: false, username: null });
  });

  it("注册成功后初始化状态变为 true，并下发 Cookie", async () => {
    const response = await bootstrap();
    expect(response.statusCode).toBe(201);
    const cookie = response.cookies.find((item) => item.name === "tb_session");
    expect(cookie).toBeDefined();
    expect(cookie?.httpOnly).toBe(true);

    const status = await app.inject({ method: "GET", url: "/api/auth/bootstrap" });
    expect(status.json()).toMatchObject({ initialized: true, username: credentials.username });
  });

  it("注册后不允许再创建第二个用户", async () => {
    expect((await bootstrap()).statusCode).toBe(201);
    const second = await app.inject({
      method: "POST",
      url: "/api/auth/bootstrap",
      payload: { username: "intruder", password: "another-strong-pass" },
    });
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
describe("跨源与代理场景（回归）", () => {
  beforeEach(async () => {
    await bootstrap();
  });

  it("桌面端 origin + Bearer 可以登录（tauri://localhost）", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/desktop-login",
      headers: { origin: "tauri://localhost", "x-toolbox-client": "desktop" },
      payload: credentials,
    });
    expect(response.statusCode).toBe(200);
    expect(typeof response.json().token).toBe("string");
  });

  it("Windows 上的 http://tauri.localhost 同样放行", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/desktop-login",
      headers: { origin: "http://tauri.localhost" },
      payload: credentials,
    });
    expect(response.statusCode).toBe(200);
  });

  it("来源与 Host 一致时放行（nginx / 同源部署）", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      headers: { host: "tool.example.com", origin: "https://tool.example.com" },
      payload: credentials,
    });
    expect(response.statusCode).toBe(200);
  });

  it("X-Forwarded-Host 与 Origin 一致时也放行（nginx 改写了 Host）", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      headers: {
        host: "127.0.0.1:3000",
        "x-forwarded-host": "tool.example.com",
        origin: "https://tool.example.com",
      },
      payload: credentials,
    });
    expect(response.statusCode).toBe(200);
  });

  it("无关来源仍然拒绝（403）", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      headers: { origin: "https://evil.example" },
      payload: credentials,
    });
    expect(response.statusCode).toBe(403);
  });

  it("预检请求返回 CORS 头", async () => {
    const response = await app.inject({
      method: "OPTIONS",
      url: "/api/auth/login",
      headers: {
        origin: "tauri://localhost",
        "access-control-request-method": "POST",
        "access-control-request-headers": "content-type,authorization",
      },
    });
    expect(response.statusCode).toBeLessThan(300);
    expect(response.headers["access-control-allow-origin"]).toBe("tauri://localhost");
  });

  it("带 X-Toolbox-Client: desktop 的 /api/auth/login 会返回 token", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      headers: { "x-toolbox-client": "desktop" },
      payload: credentials,
    });
    expect(response.statusCode).toBe(200);
    expect(typeof response.json().token).toBe("string");
  });

  it("网页端登录不返回 token（只下发 Cookie）", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      payload: credentials,
    });
    expect(response.statusCode).toBe(200);
    expect(response.json().token).toBeUndefined();
    expect(response.cookies.some((item) => item.name === "tb_session")).toBe(true);
  });
});

describe("设置与工具按数据源隔离（回归）", () => {
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

  it("PUT 设置后 GET 能读回，且默认值仍在", async () => {
    await app.inject({
      method: "PUT",
      url: "/api/settings",
      headers: { authorization: `Bearer ${token}` },
      payload: { values: { "ui.themeMode": "dark", "ui.accent": "violet" } },
    });
    const response = await app.inject({
      method: "GET",
      url: "/api/settings",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(response.json().values).toMatchObject({
      "ui.themeMode": "dark",
      "ui.accent": "violet",
      "ui.sidebarWidth": 260,
    });
  });

  it("未认证访问设置返回 401", async () => {
    const response = await app.inject({ method: "GET", url: "/api/settings" });
    expect(response.statusCode).toBe(401);
  });
});
describe("单用户：注册入口只在无用户时存在", () => {
  it("注册后 bootstrap 永远返回 initialized=true", async () => {
    await bootstrap();
    for (let i = 0; i < 3; i += 1) {
      const response = await app.inject({ method: "GET", url: "/api/auth/bootstrap" });
      expect(response.json().initialized).toBe(true);
    }
  });

  it("用注册时的用户名登录", async () => {
    await bootstrap();
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      payload: { username: credentials.username, password: credentials.password },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json().user.username).toBe(credentials.username);
  });

  it("不存在的用户名登录失败（防止创建第二个账号的错觉）", async () => {
    await bootstrap();
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      payload: { username: "someone-else", password: credentials.password },
    });
    expect(response.statusCode).toBe(401);
  });

  it("空库时桌面端也可以直接创建账号并拿到令牌", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/bootstrap",
      headers: { "x-toolbox-client": "desktop", origin: "tauri://localhost" },
      payload: credentials,
    });
    expect(response.statusCode).toBe(201);
    expect(typeof response.json().token).toBe("string");
  });

  it("自定义用户名会被正确保存并回显", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/bootstrap",
      payload: { username: "my-own-name", password: "a-strong-password" },
    });
    expect(response.statusCode).toBe(201);
    expect(response.json().user.username).toBe("my-own-name");

    const status = await app.inject({ method: "GET", url: "/api/auth/bootstrap" });
    expect(status.json()).toMatchObject({ initialized: true, username: "my-own-name" });
  });
});
describe("服务端永远要求密码（无密码模式仅限桌面端本地）", () => {
  it("bootstrap 返回 authMode=password", async () => {
    const response = await app.inject({ method: "GET", url: "/api/auth/bootstrap" });
    expect(response.json().authMode).toBe("password");
  });

  it("空密码注册被拒绝", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/bootstrap",
      payload: { username: "nobody", password: "" },
    });
    expect(response.statusCode).toBe(400);
  });

  it("短密码注册被接受（密码不限制长度）", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/bootstrap",
      payload: { username: "nobody", password: "1" },
    });
    expect(response.statusCode).toBe(201);
  });

  it("一位数字密码也能正常登录", async () => {
    await app.inject({
      method: "POST",
      url: "/api/auth/bootstrap",
      payload: { username: "tiny", password: "x" },
    });
    const response = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      payload: { username: "tiny", password: "x" },
    });
    expect(response.statusCode).toBe(200);
  });

  it("不存在免密登录接口", async () => {
    const response = await app.inject({ method: "POST", url: "/api/auth/local-session" });
    expect(response.statusCode).toBe(404);
  });

  it("不存在切换本地模式的接口", async () => {
    const response = await app.inject({
      method: "PUT",
      url: "/api/auth/local-mode",
      payload: { mode: "none" },
    });
    expect(response.statusCode).toBe(404);
  });

  it("空库时 bootstrap 也要求密码（不会自动进入）", async () => {
    const response = await app.inject({ method: "GET", url: "/api/auth/bootstrap" });
    expect(response.json()).toMatchObject({ initialized: false, authMode: "password" });
  });
});