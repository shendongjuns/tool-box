import { isTauriRuntime } from "./platform";

/**
 * 桌面端桥接层。
 *
 * - 本地数据源：Rust 侧在 127.0.0.1 的随机端口起了一个 SQLite HTTP 服务，
 *   启动时通过 invoke("local_api_port") 拿到端口。
 * - 云端数据源：请求通过 Authorization: Bearer 发往用户配置的服务器。
 *
 * 令牌按数据源分别持久化（存在本地库 settings 表的 app.tokens JSON 里）：
 *   { "local": "<token>", "cloud:http://1.2.3.4:3000": "<token>" }
 * 切换数据源只读写当前源的令牌，其它源的令牌原样保留 ——
 * 切回来不需要重新登录。
 *
 * 所有函数在网页端都是安全的空实现，页面代码无需分支。
 */
let localBaseUrl: string | null = null;
let localPort = 0;
/** 并发调用时共享同一个 Promise，避免重复 invoke。 */
let localPortPromise: Promise<number> | null = null;

/** 数据源键：本地固定 local，云端按 URL 区分（同一服务器多个名字共享一个键）。 */
export function tokenKey(source: "local" | "cloud", cloudBaseUrl: string): string {
  return source === "local" ? "local" : `cloud:${cloudBaseUrl}`;
}

async function resolveLocalPort(): Promise<number> {
  if (localPort > 0) return localPort;
  if (!isTauriRuntime()) return 0;
  if (localPortPromise) return localPortPromise;

  localPortPromise = (async () => {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      // 5 秒内拿不到端口就放弃，避免切换数据源时卡在 await 上
      const portPromise = invoke<number>("local_api_port");
      const timeout = new Promise<number>((resolve) => setTimeout(() => resolve(0), 5000));
      const port = await Promise.race([portPromise, timeout]);
      if (typeof port === "number" && port > 0) {
        localPort = port;
        localBaseUrl = `http://127.0.0.1:${port}`;
        return port;
      }
      /*
       * 失败时清掉缓存的 Promise，允许下次重试。
       *
       * 之前这里会永久缓存「已解析为 0」的 Promise，
       * 导致之后再调用 resolveLocalPort() 永远拿到 0 ——
       * 本地数据源从此不可用，只有重启应用（模块重新初始化）才能恢复。
       */
      localPortPromise = null;
      return 0;
    } catch (error) {
      console.warn("本地数据源未就绪", error);
      localPortPromise = null;
      return 0;
    }
  })();

  return localPortPromise;
}

/**
 * 带超时的 fetch：本地服务理论上一定在，但不能假设。
 *
 * 没有超时的话，一旦本地 HTTP 服务没起来，启动流程会永久挂起 ——
 * main.tsx 在 await initDesktopBridge()，整个应用白屏，
 * 表现就是「本地无法登录」。
 */
async function fetchWithTimeout(url: string, timeoutMs = 2000, init?: RequestInit) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 启动时调用一次：拿本地端口、恢复令牌表。
 *
 * **任何一步失败都不能阻塞启动** —— 最坏情况下应用以「无令牌」状态启动，
 * 用户重新登录即可，但绝不能白屏。
 */
export async function initDesktopBridge(): Promise<void> {
  if (!isTauriRuntime()) return;

  /*
   * 先无条件注入 invoke。
   *
   * 这一步必须在拿本地端口之前完成，且不依赖它是否成功：
   * 桌面端云端请求走 Rust 的 http_request 转发，如果 tauriInvoke 为 null，
   * getApi() 会退回 createFetchTransport —— 而 WebView 的 CSP
   * （connect-src 只允许 127.0.0.1 / localhost）会拦下这个请求，
   * 浏览器对被 CSP 拦截的 fetch 可能长时间不 settle，
   * 登录页就会一直显示「正在连接…」。
   */
  try {
    const { invoke } = await import("@tauri-apps/api/core");
    const { setTauriInvoke } = await import("./api-context.js");
    setTauriInvoke(invoke);
  } catch (error) {
    console.warn("注入 Tauri invoke 失败", error);
  }

  try {
    await resolveLocalPort();
  } catch {
    /* 端口拿不到就继续：后续 getApi() 会给出可读错误 */
  }

  if (!localBaseUrl) return;

  try {
    const response = await fetchWithTimeout(`${localBaseUrl}/api/app/tokens`);
    if (response.ok) {
      const data = (await response.json()) as { tokens?: Record<string, string> };
      tokens.clear();
      for (const [key, value] of Object.entries(data.tokens ?? {})) {
        if (typeof value === "string" && value.length > 0) tokens.set(key, value);
      }
    }
  } catch (error) {
    console.warn("读取桌面端令牌失败（不影响启动）", error);
  }
}

/** 内存中的令牌表（键见 tokenKey）。 */
const tokens = new Map<string, string>();

async function persist(patch: Record<string, string | null>): Promise<void> {
  if (!isTauriRuntime() || !localBaseUrl) return;
  await fetch(`${localBaseUrl}/api/app/tokens`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ tokens: patch }),
  });
}

/**
 * 本地服务地址。
 *
 * 切换数据源是同步操作，而端口是异步拿到的；如果这时还没拿到，
 * 这里会返回空串，由调用方等待 ensureLocalApi() 后再取。
 */
export function getLocalBaseUrl(): string {
  return localBaseUrl ?? "";
}

export function hasLocalApi(): boolean {
  return localPort > 0;
}

/** 确保本地端口已就绪（切换数据源前调用）。 */
export async function ensureLocalApi(): Promise<boolean> {
  const port = await resolveLocalPort();
  return port > 0;
}

/** 读取某个数据源的令牌（内存优先）。 */
export function getToken(source: "local" | "cloud", cloudBaseUrl: string): string | null {
  return tokens.get(tokenKey(source, cloudBaseUrl)) ?? null;
}

/** 写入或清除某个数据源的令牌。token 为 null 表示删除。 */
export async function setToken(
  source: "local" | "cloud",
  cloudBaseUrl: string,
  token: string | null,
): Promise<void> {
  const key = tokenKey(source, cloudBaseUrl);
  if (token) tokens.set(key, token);
  else tokens.delete(key);

  try {
    await persist({ [key]: token });
  } catch (error) {
    // 持久化失败不阻断登录：内存令牌仍然有效，只是重启后需重登
    console.warn("保存令牌失败，本次会话仍然有效", error);
  }
}

/** 当前数据源应带的 Authorization 头。 */
export function authHeaderFor(source: "local" | "cloud", cloudBaseUrl: string): Record<string, string> {
  const token = getToken(source, cloudBaseUrl);
  return token ? { authorization: `Bearer ${token}` } : {};
}