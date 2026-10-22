import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
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
  const [entering, setEntering] = useState(false);
  const attempted = useRef(false);

  const bootstrap = useQuery({
    queryKey: ["bootstrap", activeId, cloudBaseUrl],
    queryFn: () => getApi().getBootstrap(),
    retry: false,
    staleTime: 0,
  });

  /**
   * 登录方式由数据源决定：
   * - `none`：本地数据源 —— 不需要账号密码，直接以「（本地）」身份进入。
   * - `password`：云端数据源与网页端 —— 必须账号 + 密码。
   */
  const authMode = bootstrap.data?.authMode ?? "password";
  const initialized = bootstrap.data?.initialized ?? true;
  const passwordless = authMode === "none";
  const offline = bootstrap.isError;

  useEffect(() => {
    if (!passwordless || offline || attempted.current) return;
    attempted.current = true;

    // 放进异步回调，避免 effect 内同步 setState 触发级联渲染
    void (async () => {
      await Promise.resolve();
      setEntering(true);
      try {
        const result = await getApi().localSession();
        await applySession({ token: result.token, user: result.user, session: result.session });
        await navigate({ to: "/dashboard" });
      } catch {
        setEntering(false);
      }
    })();
  }, [passwordless, offline, navigate]);

  if (entering) {
    return (
      <AuthLayout title="正在进入" description="本地数据源无需登录">
        <p className="text-sm text-muted-foreground">正在打开你的本地数据…</p>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout
      title={initialized ? "欢迎回来" : "创建管理员"}
      description={
        offline
          ? "无法连接服务器，请检查地址或网络"
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
          await navigate({ to: "/dashboard" });
        }}
      />

      <div className="mt-6 flex items-center justify-center gap-2 text-xs text-muted-foreground">
        <span>数据源</span>
        <SourceSwitch />
      </div>
    </AuthLayout>
  );
}
