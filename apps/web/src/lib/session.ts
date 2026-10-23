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
 * 关键：**切换必须立刻生效**，不能等旧服务器的注销请求。
 *
 * 之前的实现是 `await logoutCurrent()` 再切换，如果旧云端不可达，
 * 用户点「使用」后要干等 3 秒超时才有反应 —— 看起来就像卡死，
 * 而且这期间再点别的数据源也是排队等待。
 *
 * 现在改为：先把注销请求发出去（不 await），立刻切换。
 * 注销请求即使失败也不影响本地状态（令牌已从本地清除）。
 *
 * 注意：这里**不清**其它数据源的本地令牌 —— 两套数据完全独立。
 */
export async function switchDataSource(id: string): Promise<boolean> {
  const state = useDataSource.getState();
  if (id === state.activeId) return false;

  const wasLoggedIn = Boolean(useAuth.getState().auth);

  // 先把旧数据源的注销请求发出去（fire-and-forget，不阻塞切换）
  if (wasLoggedIn) {
    void logoutCurrent().catch(() => {
      /* 旧服务器不可达也无所谓：本地状态已经清了 */
    });
  }

  // 立刻清本地状态与 API 缓存，让新数据源的请求用全新的连接
  invalidateApiCache();
  useAuth.getState().setAuth(null);

  // 切到本地前，确保本地服务端口已知（这一步是本地 invoke，很快）
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
