import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import { RefreshCw } from "lucide-react";
import { getApi } from "@/lib/api-context";
import { useDataSource } from "@/lib/data-source";
import { applySession } from "@/lib/session";
import { AuthLayout } from "@/components/auth/auth-layout";
import { LoginForm } from "@/components/auth/login-form";
import { SourceSwitch } from "@/components/source-switch";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/login")({
  component: LoginPage,
});

function LoginPage() {
  const navigate = useNavigate();
  const { activeId, cloudBaseUrl } = useDataSource();

  const bootstrap = useQuery({
    queryKey: ["bootstrap", activeId, cloudBaseUrl],
    /*
     * queryFn 本身设硬上限：4 秒。
     *
     * 传输层有 3 秒超时，但如果遇到传输层没能覆盖的情况
     * （例如请求被 WebView 拦截且永不 settle），
     * 这里的 Promise.race 保证查询一定会结束 ——
     * isFetching 不会无限为 true，界面不会永远「正在连接…」。
     */
    queryFn: async () => {
      const timeout = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error("连接超时，请检查地址与网络")), 4000);
      });
      return Promise.race([getApi().getBootstrap(), timeout]);
    },
    // 传输层已有超时，这里不再重试，避免「正在连接…」被拉长
    retry: false,
    staleTime: 0,
    gcTime: 0,
  });

  /*
   * 传输层对每个请求都有 3 秒硬超时（fetch: AbortController，Tauri: Promise.race），
   * 所以 bootstrap 查询一定会在 3 秒内 settle —— 不需要额外的 UI 兜底计时器。
   * isFetching 只会在这 3 秒内为 true。
   */
  const probeFailed = bootstrap.isError;
  const connecting = bootstrap.isFetching;
  // 探测失败时无法判断服务器是否已初始化：按「已初始化」处理（显示登录表单），
  // 绝不能默认成 false —— 那会显示「创建管理员」，让人误以为要注册新账号。
  const initialized = probeFailed ? true : (bootstrap.data?.initialized ?? true);

  // 标题跟随探测结果：还没拿到服务端状态时不预判
  const title = probeFailed ? "登录" : initialized ? "欢迎回来" : "创建管理员";

  const description = probeFailed
    ? "无法连接服务器，可直接尝试登录或检查地址"
    : connecting
      ? "正在连接…"
      : initialized
        ? "登录以继续"
        : "系统尚未初始化，创建唯一的账号即可开始";

  return (
    <AuthLayout title={title} description={description}>
      {/* 连接失败时给出重试入口，避免用户只能刷新整页 */}
      {probeFailed ? (
        <div className="mb-4 flex items-start gap-3 rounded-lg border border-destructive/25 bg-destructive/5 p-3">
          <div className="min-w-0 flex-1 text-xs leading-relaxed">
            <p className="font-medium text-foreground">连不上这个数据源</p>
            <p className="mt-0.5 text-muted-foreground">
              地址可能填错了，或者服务器没启动。也可以在下方直接尝试登录。
            </p>
          </div>
          <Button
            size="sm"
            variant="outline"
            onClick={() => void bootstrap.refetch()}
            disabled={connecting}
          >
            <RefreshCw className="h-3.5 w-3.5" />
            重试
          </Button>
        </div>
      ) : null}

      <LoginForm
        initialized={initialized}
        // 只在首次探测时禁用，避免连不上时连输入机会都没有
        disabled={connecting && !probeFailed}
        onSubmit={async ({ username, password }) => {
          const api = getApi();
          const result = initialized
            ? await api.login({ username, password })
            : await api.bootstrap({ username, password });

          await applySession({
            token: result.token,
            user: result.user,
            session: result.session,
          });

          toast.success(initialized ? "登录成功" : "账号已创建，已自动登录");
          await navigate({ to: "/dashboard", replace: true });
        }}
      />

      <div className="mt-6 flex items-center justify-center gap-2 text-xs text-muted-foreground">
        <span>数据源</span>
        <SourceSwitch />
      </div>
    </AuthLayout>
  );
}