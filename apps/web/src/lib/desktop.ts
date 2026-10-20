import { isTauriRuntime } from "./platform";

/**
 * 桌面端桥接层。
 *
 * - 本地数据源：Rust 侧在 127.0.0.1 的随机端口起了一个 SQLite HTTP 服务；
 *   这里在应用启动时取到端口，之后所有「本地」请求都打到它。
 * - 云端数据源：令牌存在 Tauri 的 store 里（不写 localStorage），
 *   请求通过 Authorization: Bearer 发往用户配置的服务器。
 */
let localBaseUrl: string | null = null;
let cloudToken: string | null = null;
let storeRef: { get<T>(key: string): Promise<T | undefined>; set(key: string, value: unknown): Promise<void>; delete(key: string): Promise<boolean>; save(): Promise<void> } | null = null;

export async function initDesktopBridge(): Promise<void> {
  if (!isTauriRuntime()) return;

  try {
    const { invoke } = await import("@tauri-apps/api/core");
    const port = await invoke<number>("local_api_port");
    if (typeof port === "number" && port > 0) {
      localBaseUrl = `http://127.0.0.1:${port}`;
    }
  } catch (error) {
    console.warn("本地数据源未就绪", error);
  }

  try {
    const { LazyStore } = await import("@tauri-apps/plugin-store");
    const store = new LazyStore("auth.json");
    storeRef = store as unknown as typeof storeRef;
    cloudToken = (await store.get<string>("cloudToken")) ?? null;
  } catch (error) {
    console.warn("读取桌面端令牌失败", error);
  }
}

export function getLocalBaseUrl(): string {
  return localBaseUrl ?? "http://127.0.0.1:0";
}

export function getCloudToken(): string | null {
  return cloudToken;
}

export async function setCloudToken(token: string | null): Promise<void> {
  cloudToken = token;
  if (!storeRef) return;
  if (token) {
    await storeRef.set("cloudToken", token);
  } else {
    await storeRef.delete("cloudToken");
  }
  await storeRef.save();
}

/** 桌面端请求头：本地模式无需认证头（本地服务自己校验 Bearer），云端模式带令牌。 */
export async function desktopHeaders(source: "local" | "cloud", localToken: string | null): Promise<Record<string, string>> {
  if (source === "local" && localToken) return { authorization: `Bearer ${localToken}` };
  if (source === "cloud" && cloudToken) return { authorization: `Bearer ${cloudToken}` };
  return {};
}
