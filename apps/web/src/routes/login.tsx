import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { getApi, setLocalToken } from "@/lib/api-context";
import { useAuth } from "@/lib/auth-session";
import { canSwitchSource, DATA_SOURCES } from "@/lib/source";
import { useDataSource } from "@/lib/data-source";
import { setCloudToken } from "@/lib/desktop";
import { AuthLayout } from "@/components/auth/auth-layout";
import { LoginForm } from "@/components/auth/login-form";
import { SourceSwitch } from "@/components/source-switch";

export const Route = createFileRoute("/login")({
  component: LoginPage,
});

function LoginPage() {
  const navigate = useNavigate();
  const setAuth = useAuth((state) => state.setAuth);
  const { source, cloudBaseUrl, setCloudBaseUrl, setSource } = useDataSource();
  const [serverUrl, setServerUrl] = useState(cloudBaseUrl);
  const [savingServer, setSavingServer] = useState(false);

  const bootstrap = useQuery({
    queryKey: ["bootstrap", source, cloudBaseUrl],
    queryFn: () => getApi().getBootstrap(),
    retry: false,
    staleTime: 5_000,
  });

  const initialized = bootstrap.data?.initialized ?? true;
  const sourceInfo = DATA_SOURCES[source];
  const offline = bootstrap.isError;

  async function updateServer() {
    setSavingServer(true);
    try {
      setCloudBaseUrl(serverUrl);
      await new Promise((resolve) => setTimeout(resolve, 100));
      await bootstrap.refetch();
      toast.success("服务器地址已更新");
    } finally {
      setSavingServer(false);
    }
  }

  return (
    <AuthLayout
      title={initialized ? "欢迎回来" : "创建你的账号"}
      description={
        offline
          ? `无法连接${sourceInfo.label}，请检查服务器地址或网络`
          : initialized
            ? `登录以继续使用${sourceInfo.label}`
            : "这是首次使用，设置一个账号即可开始"
      }
      badge={<SourceSwitch compact onChanged={() => setAuth(null)} />}
    >
      <LoginForm
        source={source}
        initialized={initialized}
        onSubmit={async ({ username, password, setupToken }) => {
          const result = !initialized
            ? await getApi().bootstrap({
                username,
                password,
                ...(setupToken ? { setupToken } : {}),
              })
            : await getApi().login({ username, password });

          // 桌面端把令牌落到本地（云端存 Tauri store，本地存内存），
          // 之后的请求由 getApi() 自动带上 Authorization 头。
          if (result.token) {
            if (source === "local") setLocalToken(result.token);
            else await setCloudToken(result.token);
          }

          const me = await getApi().me();
          setAuth({ user: me.user, session: me.session });
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
                  placeholder="https://tool.example.com"
                  className="h-9 flex-1 rounded-md border border-input bg-card px-2.5 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]"
                />
                <button
                  type="button"
                  onClick={() => void updateServer()}
                  disabled={savingServer || serverUrl === cloudBaseUrl}
                  className="h-9 rounded-md border border-border px-3 text-xs font-medium transition-colors hover:bg-accent disabled:opacity-50"
                >
                  保存
                </button>
              </div>
              <p className="mt-1.5 text-[11px] text-muted-foreground">
                切换服务器后需要重新登录。
              </p>
            </div>
          ) : null
        }
      />
      {canSwitchSource() ? (
        <p className="mt-6 text-center text-xs text-muted-foreground">
          当前使用{" "}
          <span className="font-medium text-foreground">{sourceInfo.label}</span>
          {" · "}
          <button
            type="button"
            className="font-medium text-primary underline-offset-2 hover:underline"
            onClick={() => {
              setSource(source === "local" ? "cloud" : "local");
              setAuth(null);
            }}
          >
            切换到{DATA_SOURCES[source === "local" ? "cloud" : "local"].label}
          </button>
        </p>
      ) : null}
    </AuthLayout>
  );
}