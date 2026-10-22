import { isTauriRuntime } from "./platform";

/**
 * 桌面端桥接层。
 *
 * - 本地数据源：Rust 侧在 127.0.0.1 的随机端口起了一个 SQLite HTTP 服务，
 *   启动时通过 invoke("local_api_port") 拿到端口。
 * - 云端数据源：令牌存在 Tauri 的 store 里（不写 localStorage），
 *   请求通过 Authorization: Bearer 发往用户配置的服务器。
 *
 * 所有函数在网页端都是安全的空实现，页面代码无需分支。
 */
let localBaseUrl: string | null = null;
let cloudToken: string | null = null;
let localToken: string | null = null;
let localPort = 0;
/** 并发调用时共享同一个 Promise，避免重复 invoke。 */
let localPortPromise: Promise<number> | null = null;

interface TokenStore {
  get<T>(key: string): Promise<T | undefined>;
  set(key: string, value: unknown): Promise<void>;
  delete(key: string): Promise<boolean>;
  save(): Promise<void>;
}

let storeRef: TokenStore | null = null;

async function resolveLocalPort(): Promise<number> {
  if (localPort > 0) return localPort;
  if (!isTauriRuntime()) return 0;
  if (localPortPromise) return localPortPromise;

  localPortPromise = (async () => {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const port = await invoke<number>("local_api_port");
      if (typeof port === "number" && port > 0) {
        localPort = port;
        localBaseUrl = `http://127.0.0.1:${port}`;
      }
      return localPort;
    } catch (error) {
      console.warn("本地数据源未就绪", error);
      return 0;
    }
  })();

  return localPortPromise;
}

/** 启动时调用一次：拿本地端口、恢复令牌。 */
export async function initDesktopBridge(): Promise<void> {
  if (!isTauriRuntime()) return;

  await resolveLocalPort();

  try {
    const { LazyStore } = await import("@tauri-apps/plugin-store");
    const store = new LazyStore("auth.json");
    storeRef = store as unknown as TokenStore;
    cloudToken = (await store.get<string>("cloudToken")) ?? null;
    localToken = (await store.get<string>("localToken")) ?? null;
  } catch (error) {
    console.warn("读取桌面端令牌失败", error);
  }
}

/**
 * 本地服务地址。
 *
 * 切换数据源是同步操作，而端口是异步拿到的；如果这时还没拿到，
 * 这里会返回空串，由调用方等待 `ensureLocalApi()` 后再取。
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

export function getCloudToken(): string | null {
  return cloudToken;
}

export function getLocalToken(): string | null {
  return localToken;
}

async function persist(key: string, value: string | null): Promise<void> {
  if (!storeRef) return;
  if (value) await storeRef.set(key, value);
  else await storeRef.delete(key);
  await storeRef.save();
}

export async function setCloudToken(token: string | null): Promise<void> {
  cloudToken = token;
  await persist("cloudToken", token);
}

/** 本地数据源的会话令牌：与云端分开存，切数据源不会互相顶掉。 */
export async function setLocalSessionToken(token: string | null): Promise<void> {
  localToken = token;
  await persist("localToken", token);
}

/** 当前数据源应带的 Authorization 头。 */
export function authHeaderFor(source: "local" | "cloud"): Record<string, string> {
  const token = source === "local" ? localToken : cloudToken;
  return token ? { authorization: `Bearer ${token}` } : {};
}
