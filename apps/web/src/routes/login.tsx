import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import { getApi } from "@/lib/api-context";
import { useDataSource } from "@/lib/data-source";
import { applySession } from "@/lib/session";
import { AuthLayout } from "@/components/auth/auth-layout";
import { LoginForm } from "@/components/auth/login-form";
import { SourceSwitch } from "@/components/source-switch";

export const Route = createFileRoute("/login")({
  component: LoginPage,
});

function LoginPage() {
  const navigate = useNavigate();
  const { activeId, cloudBaseUrl } = useDataSource();

  const bootstrap = useQuery({
    queryKey: ["bootstrap", activeId, cloudBaseUrl],
    queryFn: () => getApi().getBootstrap(),
    retry: false,
    staleTime: 0,
  });

  // 所有数据源（本地 / 云端 / 网页端）登录方式完全一致：账号 + 密码。
  const initialized = bootstrap.data?.initialized ?? true;
  // bootstrap 只是探测：失败不代表登录不可用，因此不禁用表单，
  // 只提示「连接状态未知」；查询中才禁用，避免重复提交。
  const probeFailed = bootstrap.isError;
  const offline = bootstrap.isLoading;

  // 标题跟随探测结果：还没拿到服务端状态时不预判，
  // 避免把「已初始化」的服务器误标成「创建管理员」。
  const title = probeFailed ? "登录" : initialized ? "欢迎回来" : "创建管理员";

  return (
    <AuthLayout
      title={title}
      description={
        probeFailed
          ? "无法确认服务器状态，可直接尝试登录"
          : offline
            ? "正在连接…"
            : initialized
              ? "登录以继续"
              : "系统尚未初始化，创建唯一的账号即可开始"
      }
    >
      <LoginForm
        initialized={initialized}
        disabled={offline}
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
          // replace：避免 WebView 历史里堆积 /login → /dashboard → /login
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