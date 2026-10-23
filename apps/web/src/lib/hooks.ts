import { useQuery } from "@tanstack/react-query";
import type { DashboardResponse, GetSettingsResponse } from "@toolbox/contracts";
import { useApi } from "./api-context";
import { useAuth } from "./auth-session";
import { currentSourceKey, useDataSource } from "./data-source";

/**
 * 查询键必须带数据源前缀。
 *
 * 不同数据源是完全独立的数据集，切换后若沿用同一个缓存键，
 * 会把上一个数据源的内容显示在新数据源里。
 */
export const queryKeys = {
  settings: (key: string) => ["settings", key] as const,
  dashboard: (key: string) => ["dashboard", key] as const,
  tools: (key: string) => ["tools", key] as const,
  sessions: (key: string) => ["sessions", key] as const,
  servers: (key: string) => ["servers", key] as const,
  bootstrap: (key: string) => ["bootstrap", key] as const,
};

export function useCurrentSourceKey(): string {
  const activeId = useDataSource((state) => state.activeId);
  const cloudBaseUrl = useDataSource((state) => state.cloudBaseUrl);
  return currentSourceKey({ activeId, cloudBaseUrl });
}

export function useSettingsQuery() {
  const api = useApi();
  const key = useCurrentSourceKey();
  const authed = useAuth((state) => state.auth !== null);

  return useQuery<GetSettingsResponse>({
    queryKey: queryKeys.settings(key),
    queryFn: () => api.getSettings(),
    enabled: authed,
    staleTime: 30_000,
  });
}

export function useDashboardQuery() {
  const api = useApi();
  const key = useCurrentSourceKey();
  const authed = useAuth((state) => state.auth !== null);

  return useQuery<DashboardResponse>({
    queryKey: queryKeys.dashboard(key),
    queryFn: () => api.dashboard(),
    enabled: authed,
    staleTime: 15_000,
  });
}