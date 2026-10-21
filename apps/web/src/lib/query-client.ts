import { QueryClient } from "@tanstack/react-query";
import { ApiError } from "@toolbox/api-client";

export function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        gcTime: 5 * 60_000,
        refetchOnWindowFocus: false,
        retry: (failureCount, error) => {
          if (error instanceof ApiError) {
            // 断网 / 地址错误最多再试一次；4xx 一律不重试
            if (error.isNetworkError) return failureCount < 1;
            if (error.status >= 400 && error.status < 500) return false;
          }
          return failureCount < 2;
        },
      },
      mutations: { retry: false },
    },
  });
}
