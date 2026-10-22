import { invalidateApiCache } from "./api-context";
import { useAuth } from "./auth-session";
import { useDataSource } from "./data-source";
import { setCloudToken, setLocalSessionToken } from "./desktop";
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

/** 退出登录：清空令牌与内存状态。 */
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
 * 切换数据源：换连接 + 清缓存 + 退回登录页。
 *
 * 两套数据本身互不影响，但登录态必须重来，否则会拿旧服务器的令牌打新服务器。
 */
export async function switchDataSource(id: string): Promise<void> {
  const changed = useDataSource.getState().select(id);
  if (!changed) return;
  useAuth.getState().setAuth(null);
  invalidateApiCache();
}
