import { invalidateApiCache } from "./api-context";
import { useAuth } from "./auth-session";
import { useDataSource } from "./data-source";
import { ensureLocalApi, setCloudToken, setLocalSessionToken } from "./desktop";
import { isTauriRuntime } from "./platform";
import type { PublicUser, SessionInfo } from "@toolbox/contracts";

/**
 * 登录成功后的收尾：保存令牌、让 API 缓存重建、写入内存登录态。
 *
 * 桌面端：本地与各云端地址的令牌按数据源分别保存，切换时不会互相顶掉。
 * 网页端：服务端已下发 Cookie，这里只更新内存状态。
 */
export async function applySession(input: {
  token?: string;
  user: PublicUser;
  session: SessionInfo;
}): Promise<void> {
  const { type } = useDataSource.getState();

  if (isTauriRuntime() && input.token) {
    try {
      if (type === "local") await setLocalSessionToken(input.token);
      else await setCloudToken(input.token);
    } catch (error) {
      // 令牌持久化失败不应该阻断登录：内存里的令牌仍然有效
      console.warn("保存登录令牌失败，本次会话仍然有效", error);
    }
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
  await clearSession();
}

/** 清空本地令牌与内存状态（不请求服务端）。 */
export async function clearSession(): Promise<void> {
  if (isTauriRuntime()) {
    try {
      await setCloudToken(null);
      await setLocalSessionToken(null);
    } catch {
      // 清不掉也不影响内存状态
    }
  }
  invalidateApiCache();
  useAuth.getState().setAuth(null);
}

/**
 * 切换数据源。
 *
 * 顺序很重要：
 * 1. 先用「当前」数据源的连接注销会话（否则旧令牌会一直留在服务端）
 * 2. 再切换数据源
 * 3. 最后清缓存并退回登录页
 */
export async function switchDataSource(id: string): Promise<boolean> {
  const state = useDataSource.getState();
  if (id === state.activeId) return false;

  // 只有已登录时才需要注销
  if (useAuth.getState().auth) {
    await logoutCurrent();
  } else {
    await clearSession();
  }

  // 切到本地前，先确保本地服务端口已知，否则首个请求会打到占位地址上
  const target = state.cloudSources.find((item) => item.id === id);
  if (!target) {
    await ensureLocalApi();
  }

  state.select(id);
  return true;
}