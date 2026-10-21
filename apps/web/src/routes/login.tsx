import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { getApi, invalidateApiCache } from "@/lib/api-context";
import { useAuth } from "@/lib/auth-session";
import { useDataSource } from "@/lib/data-source";
import { applySession, switchDataSource } from "@/lib/session";
import { canSwitchSource, DATA_SOURCES } from "@/lib/source";
import { AuthLayout } from "@/components/auth/auth-layout";
import { LoginForm } from "@/components/auth/login-form";
import { SourceSwitch } from "@/components/source-switch";

export const Route = createFileRoute("/login")({
  component: LoginPage,
});

function LoginPage() {
  const navigate = useNavigate();
  const { source, cloudBaseUrl, setCloudBaseUrl } = useDataSource();
  const [serverUrl, setServerUrl] = useState(cloudBaseUrl);
  const [savingServer, setSavingServer] = useState(false);
  const [autoEntering, setAutoEntering] = useState(false);
  const attempted = useRef(false);

  const bootstrap = useQuery({
    queryKey: ["bootstrap", source, cloudBaseUrl],
    queryFn: () => getApi().getBootstrap(),
    retry: false,
    staleTime: 0,
  });

  /**
   * 只有明确拿到 false 才显示注册表单。
   *
   * 查询中 / 查询失败时按「已初始化」显示登录，避免把用户误导向注册页。
   */
  const initialized = bootstrap.data?.initialized ?? true;
  const passwordless = bootstrap.data?.passwordless ?? false;
  const sourceInfo = DATA_SOURCES[source];
  const offline = bootstrap.isError;

  /**
   * 桌面端本地数据源的无密码模式：直接签发会话进入，不显示登录页。
   *
   * 只在「本地 + 无密码 + 已初始化」时触发，且每个挂载周期只尝试一次，
   * 失败则退回普通登录表单（例如用户刚开启了密码模式）。
   */
  useEffect(() => {
    if (!passwordless || !initialized || offline || attempted.current) return;
    if (source !== "local") return;
    attempted.current = true;

    // setState 放进异步回调里，避免 effect 内同步触发级联渲染
    void (async () => {
      await Promise.resolve();
      setAutoEntering(true);
      try {
        const result = await getApi().localSession();
        await applySession({ token: result.token, user: result.user, session: result.session });
        await navigate({ to: "/dashboard" });
      } catch {
        setAutoEntering(false);
      }
    })();
  }, [passwordless, initialized, offline, source, navigate]);

  async function updateServer() {
    const next = serverUrl.trim().replace(/\/$/, "");
    if (!next) {
      toast.error("请填写服务器地址");
      return;
    }
    setSavingServer(true);
    try {
      setCloudBaseUrl(next);
      setServerUrl(next);
      invalidateApiCache();
      useAuth.getState().setAuth(null);
      await bootstrap.refetch();
      toast.success("服务器地址已更新");
    } finally {
      setSavingServer(false);
    }
  }

  if (autoEntering) {
    return (
      <AuthLayout title="正在进入" description="本地数据源已开启无密码模式">
        <p className="text-sm text-muted-foreground">正在打开你的本地数据…</p>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout
      title={initialized ? "欢迎回来" : "创建管理员"}
      description={
        offline
          ? `无法连接${sourceInfo.label}，请检查服务器地址或网络`
          : initialized
            ? `登录以继续使用${sourceInfo.label}`
            : "系统尚未初始化，创建唯一的账号即可开始"
      }
      badge={<SourceSwitch compact />}
    >
      <LoginForm
        source={source}
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
        extra={
          canSwitchSource() && source === "cloud" ? (
            <div className="rounded-lg border border-border bg-muted/40 p-3">
              <label className="text-xs font-medium text-muted-foreground" htmlFor="server-url">
                服务器地址
              </label>
              <div className="mt-1.5 flex gap-2">
                <input
                  id="server-url"
                  value={serverUrl}
                  onChange={(event) => setServerUrl(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      void updateServer();
                    }
                  }}
                  placeholder="http://127.0.0.1:3000"
                  className="h-9 flex-1 rounded-md border border-input bg-card px-2.5 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]"
                />
                <button
                  type="button"
                  onClick={() => void updateServer()}
                  disabled={savingServer || serverUrl.trim() === cloudBaseUrl}
                  className="h-9 rounded-md border border-border px-3 text-xs font-medium transition-colors hover:bg-accent disabled:opacity-50"
                >
                  保存
                </button>
              </div>
              <p className="mt-1.5 text-[11px] text-muted-foreground">切换后需要重新登录。</p>
            </div>
          ) : null
        }
      />

      {canSwitchSource() ? (
        <p className="mt-6 text-center text-xs text-muted-foreground">
          当前使用 <span className="font-medium text-foreground">{sourceInfo.label}</span>
          {" · "}
          <button
            type="button"
            className="font-medium text-primary underline-offset-2 hover:underline"
            onClick={() => void switchDataSource(source === "local" ? "cloud" : "local")}
          >
            切换到{DATA_SOURCES[source === "local" ? "cloud" : "local"].label}
          </button>
        </p>
      ) : null}
    </AuthLayout>
  );
}