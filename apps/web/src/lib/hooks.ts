import { useQuery } from "@tanstack/react-query";
import type { DashboardResponse, GetSettingsResponse } from "@toolbox/contracts";
import { useApi } from "./api-context";
import { useAuth } from "./auth-session";
import { sourceKey, useDataSource } from "./data-source";

/**
 * 查询键必须带数据源前缀。
 *
 * 本地与云端是两套完全独立的数据，切换后若沿用同一个缓存键，
 * 会把云端的数据显示在本地模式下（反之亦然）。
 */
export const queryKeys = {
  settings: (key: string) => ["settings", key] as const,
  dashboard: (key: string) => ["dashboard", key] as const,
  tools: (key: string) => ["tools", key] as const,
  sessions: (key: string) => ["sessions", key] as const,
  bootstrap: (key: string) => ["bootstrap", key] as const,
};

export function useCurrentSourceKey(): string {
  const source = useDataSource((state) => state.source);
  const cloudBaseUrl = useDataSource((state) => state.cloudBaseUrl);
  return sourceKey(source, cloudBaseUrl);
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
