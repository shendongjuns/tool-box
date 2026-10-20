import { create } from "zustand";
import type { PublicUser, SessionInfo } from "@toolbox/contracts";

export interface AuthSnapshot {
  user: PublicUser;
  session: SessionInfo;
}

export interface AuthState {
  auth: AuthSnapshot | null;
  /** 正在恢复登录态（刷新页面时） */
  restoring: boolean;
  setAuth: (auth: AuthSnapshot | null) => void;
  setRestoring: (value: boolean) => void;
}

/**
 * 登录态只放内存，不放 localStorage：
 * Cookie / Bearer 才是真凭证，前端状态刷新后由 /api/auth/me 恢复。
 */
export const useAuth = create<AuthState>((set) => ({
  auth: null,
  restoring: true,
  setAuth: (auth) => set({ auth, restoring: false }),
  setRestoring: (restoring) => set({ restoring }),
}));
