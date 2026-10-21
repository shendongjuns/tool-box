import { invalidateApiCache } from "./api-context";
import { useAuth } from "./auth-session";
import { setCloudToken, setLocalSessionToken } from "./desktop";
import { useDataSource } from "./data-source";
import { isTauriRuntime } from "./platform";
import type { PublicUser, SessionInfo } from "@toolbox/contracts";

/**
 * 登录成功后的收尾：保存令牌、让 API 缓存重建、写入内存登录态。
 *
 * 桌面端：本地与云端令牌分开保存，切换数据源时不会互相顶掉。
 * 网页端：服务端已下发 Cookie，这里只更新内存状态。
 */
export async function applySession(input: {
  token?: string;
  user: PublicUser;
  session: SessionInfo;
}): Promise<void> {
  const source = useDataSource.getState().source;

  if (isTauriRuntime() && input.token) {
    if (source === "local") await setLocalSessionToken(input.token);
    else await setCloudToken(input.token);
  }

  invalidateApiCache();
  useAuth.getState().setAuth({ user: input.user, session: input.session });
}

/** 退出登录：清空令牌与内存状态。 */
export async function clearSession(): Promise<void> {
  if (isTauriRuntime()) {
    await setCloudToken(null);
    await setLocalSessionToken(null);
  }
  invalidateApiCache();
  useAuth.getState().setAuth(null);
}

/** 切换数据源：只换连接，两套数据本身互不影响。 */
export async function switchDataSource(next: "local" | "cloud"): Promise<void> {
  useDataSource.getState().setSource(next);
  invalidateApiCache();
  useAuth.getState().setAuth(null);
}
