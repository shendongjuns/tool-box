import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { BootstrapStatus, DashboardResponse, GetSettingsResponse } from "@toolbox/contracts";
import { useApi } from "./api-context";
import { useAuth } from "./auth-session";

export const queryKeys = {
  bootstrap: (source: string) => ["bootstrap", source] as const,
  me: (source: string) => ["me", source] as const,
  settings: (source: string) => ["settings", source] as const,
  tools: (source: string) => ["tools", source] as const,
  dashboard: (source: string) => ["dashboard", source] as const,
  sessions: (source: string) => ["sessions", source] as const,
};

/** 首次注册状态（决定登录页还是注册页）。 */
export function useBootstrap() {
  const api = useApi();
  const source = useAuth((state) => state.auth !== null);
  return useQuery<BootstrapStatus>({
    queryKey: queryKeys.bootstrap(String(source)),
    queryFn: () => api.getBootstrap(),
    staleTime: 10_000,
    retry: false,
  });
}

export function useSettings() {
  const api = useApi();
  return useQuery<GetSettingsResponse>({
    queryKey: queryKeys.settings("current"),
    queryFn: () => api.getSettings(),
    enabled: useAuth((state) => state.auth !== null),
  });
}

export function useDashboard() {
  const api = useApi();
  return useQuery<DashboardResponse>({
    queryKey: queryKeys.dashboard("current"),
    queryFn: () => api.dashboard(),
    enabled: useAuth((state) => state.auth !== null),
  });
}

export function useInvalidateAll() {
  const client = useQueryClient();
  return () => client.invalidateQueries();
}
