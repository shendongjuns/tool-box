import { invalidateApiCache } from "./api-context";
import { useAuth } from "./auth-session";
import { useDataSource } from "./data-source";
import { ensureLocalApi, getToken, setToken } from "./desktop";
import { isTauriRuntime } from "./platform";
import type { PublicUser, SessionInfo } from "@toolbox/contracts";

/**
 * 登录成功后的收尾：保存令牌、让 API 缓存重建、写入内存登录态。
 *
 * 令牌按数据源分别持久化（本地库 app.tokens），因此切换数据源
 * 不会把另一个数据源的令牌顶掉。
 */
export async function applySession(input: {
  token?: string;
  user: PublicUser;
  session: SessionInfo;
}): Promise<void> {
  const { type, cloudBaseUrl } = useDataSource.getState();

  if (isTauriRuntime() && input.token) {
    await setToken(type, cloudBaseUrl, input.token);
  }

  invalidateApiCache();
  useAuth.getState().setAuth({ user: input.user, session: input.session });
}

/**
 * 退出登录。
 *
 * 先让服务端注销当前会话（把 sessions.revoked_at 置位），再清本地状态 ——
 * 只清本地的话，那个令牌在 30 天内仍然有效，属于「假退出」。
 * 服务端不可达时也要让本地退出，不能把用户困在已登录界面。
 */
export async function logoutCurrent(): Promise<void> {
  try {
    const { getApi } = await import("./api-context");
    await getApi().logout();
  } catch {
    // 网络问题 / 令牌已失效：继续清理本地状态
  }

  const { type, cloudBaseUrl } = useDataSource.getState();
  if (isTauriRuntime()) {
    // 只删当前数据源的令牌；其它数据源的令牌保留，切回去无需重登
    await setToken(type, cloudBaseUrl, null);
  }

  invalidateApiCache();
  useAuth.getState().setAuth(null);
}

/**
 * 切换数据源。
 *
 * 顺序很重要：
 * 1. 已登录时先用「当前」数据源连接注销会话（否则旧令牌会一直留在服务端）
 * 2. 再切换数据源
 * 3. 最后清缓存并退回登录页
 *
 * 注意：这里**不清**其它数据源的本地令牌 —— 两套数据完全独立。
 */
export async function switchDataSource(id: string): Promise<boolean> {
  const state = useDataSource.getState();
  if (id === state.activeId) return false;

  // 只有已登录时才需要注销
  if (useAuth.getState().auth) {
    await logoutCurrent();
  } else {
    invalidateApiCache();
    useAuth.getState().setAuth(null);
  }

  // 切到本地前，先确保本地服务端口已知，否则首个请求会打到占位地址上
  const target = state.cloudSources.find((item) => item.id === id);
  if (!target) {
    await ensureLocalApi();
  }

  state.select(id);
  return true;
}

/** 取当前数据源的令牌（桌面端用）。 */
export function currentToken(): string | null {
  const { type, cloudBaseUrl } = useDataSource.getState();
  return isTauriRuntime() ? getToken(type, cloudBaseUrl) : null;
}
