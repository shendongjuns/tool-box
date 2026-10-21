import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { z } from "zod";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Cloud, Database, LogOut, Monitor, Moon, Palette, Sun } from "lucide-react";
import { toast } from "sonner";
import type { Accent, ThemeMode } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { useAuth } from "@/lib/auth-session";
import { queryKeys, useCurrentSourceKey, useSettingsQuery } from "@/lib/hooks";
import { clearSession, switchDataSource } from "@/lib/session";
import { useDataSource } from "@/lib/data-source";
import { canSwitchSource, DATA_SOURCES } from "@/lib/source";
import { isDesktop } from "@/lib/platform";
import { useTheme } from "@/lib/theme";
import { cn, formatDateTime } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, FieldHint, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

const tabSchema = z.enum(["general", "appearance", "account", "about"]).catch("general");
type SettingsTab = z.infer<typeof tabSchema>;

export const Route = createFileRoute("/_app/settings")({
  // 支持 /settings?tab=appearance 直达
  validateSearch: (search: Record<string, unknown>) => ({
    tab: tabSchema.parse(search.tab),
  }),
  component: SettingsPage,
});

const accents: { id: Accent; label: string; color: string }[] = [
  { id: "indigo", label: "靛蓝", color: "oklch(0.55 0.19 275)" },
  { id: "violet", label: "紫罗兰", color: "oklch(0.58 0.2 300)" },
  { id: "emerald", label: "翡翠", color: "oklch(0.6 0.13 165)" },
  { id: "amber", label: "琥珀", color: "oklch(0.72 0.16 75)" },
  { id: "rose", label: "玫瑰", color: "oklch(0.6 0.19 15)" },
  { id: "slate", label: "石板", color: "oklch(0.5 0.02 260)" },
];

function SettingsPage() {
  const { tab } = Route.useSearch();
  const navigate = useNavigate();

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">设置</h1>
        <p className="mt-1 text-sm text-muted-foreground">外观、数据源、账户与安全</p>
      </header>

      <Tabs
        value={tab}
        onValueChange={(value) =>
          void navigate({ to: "/settings", search: { tab: value as SettingsTab } })
        }
      >
        <TabsList>
          <TabsTrigger value="general">通用</TabsTrigger>
          <TabsTrigger value="appearance">外观</TabsTrigger>
          <TabsTrigger value="account">账户</TabsTrigger>
          <TabsTrigger value="about">关于</TabsTrigger>
        </TabsList>

        <TabsContent value="general">
          <GeneralTab />
        </TabsContent>
        <TabsContent value="appearance">
          <AppearanceTab />
        </TabsContent>
        <TabsContent value="account">
          <AccountTab />
        </TabsContent>
        <TabsContent value="about">
          <AboutTab />
        </TabsContent>
      </Tabs>
    </div>
  );
}

function GeneralTab() {
  const source = useDataSource((state) => state.source);
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();
  const navigate = useNavigate();
  const settings = useSettingsQuery();

  const saveSetting = useMutation({
    mutationFn: (values: Record<string, string | number | boolean>) => api.putSettings({ values }),
    onSuccess: () => {
      toast.success("设置已保存");
      void queryClient.invalidateQueries({ queryKey: queryKeys.settings(sourceKey) });
    },
  });

  const closeBehavior = String(settings.data?.values["ui.closeBehavior"] ?? "ask");

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Database className="h-4 w-4 text-primary" />
            数据源
          </CardTitle>
          <CardDescription>
            两套数据彼此独立、互不覆盖。切换后需要重新登录对应数据源。
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {(["local", "cloud"] as const).map((id) => {
            const info = DATA_SOURCES[id];
            const active = source === id;
            const Icon = id === "local" ? Database : Cloud;
            return (
              <button
                key={id}
                type="button"
                disabled={!canSwitchSource() || active}
                onClick={async () => {
                  await switchDataSource(id);
                  toast.success(`已切换到${info.label}，请重新登录`);
                  await navigate({ to: "/login" });
                }}
                className={cn(
                  "flex w-full items-start gap-3 rounded-lg border p-4 text-left transition-colors",
                  active
                    ? "border-primary/40 bg-primary/5"
                    : "border-border hover:bg-accent disabled:cursor-not-allowed disabled:opacity-60",
                )}
              >
                <div
                  className={cn(
                    "grid h-9 w-9 shrink-0 place-items-center rounded-lg",
                    active ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground",
                  )}
                >
                  <Icon className="h-4 w-4" />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium">{info.label}</p>
                    {active ? <Badge variant="success">使用中</Badge> : null}
                    {!canSwitchSource() && id === "local" ? (
                      <Badge variant="outline">仅桌面端</Badge>
                    ) : null}
                  </div>
                  <p className="mt-0.5 text-xs text-muted-foreground">{info.description}</p>
                </div>
                {active ? <Check className="h-4 w-4 shrink-0 text-primary" /> : null}
              </button>
            );
          })}
        </CardContent>
      </Card>

      {isDesktop() ? (
        <Card>
          <CardHeader>
            <CardTitle>桌面行为</CardTitle>
            <CardDescription>仅在桌面端生效</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-medium">关闭窗口时</p>
                <p className="text-xs text-muted-foreground">决定点击关闭按钮后的行为</p>
              </div>
              <select
                value={closeBehavior}
                onChange={(event) => saveSetting.mutate({ "ui.closeBehavior": event.target.value })}
                className="h-9 rounded-md border border-border bg-card px-2 text-sm"
              >
                <option value="ask">每次询问</option>
                <option value="tray">最小化到托盘</option>
                <option value="quit">直接退出</option>
              </select>
            </div>
            <Separator />
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-medium">紧凑侧栏</p>
                <p className="text-xs text-muted-foreground">只显示图标，为内容留出更多空间</p>
              </div>
              <Switch
                checked={Boolean(settings.data?.values["ui.sidebarCollapsed"])}
                onCheckedChange={(checked) => saveSetting.mutate({ "ui.sidebarCollapsed": checked })}
              />
            </div>
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}

function AppearanceTab() {
  const theme = useTheme();
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();

  const persist = (values: Record<string, string>) => {
    void api
      .putSettings({ values })
      .then(() => queryClient.invalidateQueries({ queryKey: queryKeys.settings(sourceKey) }))
      .catch((error: unknown) => {
        toast.error(error instanceof Error ? error.message : "保存失败");
      });
  };

  const modes: { id: ThemeMode; label: string; icon: typeof Sun }[] = [
    { id: "light", label: "浅色", icon: Sun },
    { id: "dark", label: "深色", icon: Moon },
    { id: "system", label: "跟随系统", icon: Monitor },
  ];

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Palette className="h-4 w-4 text-primary" />
            主题模式
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-3 gap-3">
            {modes.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => {
                  theme.setMode(id);
                  persist({ "ui.themeMode": id });
                }}
                className={cn(
                  "flex flex-col items-center gap-2 rounded-lg border p-4 transition-colors",
                  theme.mode === id
                    ? "border-primary bg-primary/5 text-primary"
                    : "border-border text-muted-foreground hover:bg-accent",
                )}
              >
                <Icon className="h-5 w-5" />
                <span className="text-sm font-medium">{label}</span>
              </button>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>强调色</CardTitle>
          <CardDescription>影响按钮、链接与选中态的颜色</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-3">
            {accents.map((accent) => (
              <button
                key={accent.id}
                type="button"
                onClick={() => {
                  theme.setAccent(accent.id);
                  persist({ "ui.accent": accent.id });
                }}
                className={cn(
                  "flex items-center gap-2 rounded-lg border px-3 py-2 text-sm transition-colors",
                  theme.accent === accent.id ? "border-primary" : "border-border hover:bg-accent",
                )}
              >
                <span
                  className="h-4 w-4 rounded-full"
                  style={{ backgroundColor: accent.color }}
                  aria-hidden
                />
                {accent.label}
                {theme.accent === accent.id ? <Check className="h-3.5 w-3.5 text-primary" /> : null}
              </button>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

function AccountTab() {
  const api = useApi();
  const user = useAuth((state) => state.auth?.user);
  const session = useAuth((state) => state.auth?.session);
  const sourceKey = useCurrentSourceKey();
  const navigate = useNavigate();
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [pending, setPending] = useState(false);

  const sessions = useQuery({
    queryKey: queryKeys.sessions(sourceKey),
    queryFn: () => api.listSessions(),
    staleTime: 10_000,
  });

  async function changePassword() {
    if (newPassword.length < 10) {
      toast.error("新密码至少 10 个字符");
      return;
    }
    if (newPassword !== confirmPassword) {
      toast.error("两次输入的新密码不一致");
      return;
    }
    setPending(true);
    try {
      await api.changePassword({ currentPassword, newPassword });
      toast.success("密码已更新，其他设备已下线");
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      void sessions.refetch();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "修改失败");
    } finally {
      setPending(false);
    }
  }

  async function logout() {
    try {
      await api.logout();
    } catch {
      // 服务端不可达也要能退出
    }
    await clearSession();
    await navigate({ to: "/login" });
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>账户信息</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          <Row label="用户名" value={user?.username ?? "—"} />
          <Row label="显示名称" value={user?.displayName ?? "—"} />
          <Row label="创建时间" value={user ? formatDateTime(user.createdAt) : "—"} />
          <Row label="会话到期" value={session ? formatDateTime(session.expiresAt) : "—"} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>修改密码</CardTitle>
          <CardDescription>修改后，其他设备上的登录会立即失效</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <Field>
            <FieldLabel htmlFor="current">当前密码</FieldLabel>
            <Input
              id="current"
              type="password"
              autoComplete="current-password"
              value={currentPassword}
              onChange={(event) => setCurrentPassword(event.target.value)}
            />
          </Field>
          <Field>
            <FieldLabel htmlFor="new">新密码</FieldLabel>
            <Input
              id="new"
              type="password"
              autoComplete="new-password"
              value={newPassword}
              onChange={(event) => setNewPassword(event.target.value)}
            />
            <FieldHint>至少 10 个字符</FieldHint>
          </Field>
          <Field>
            <FieldLabel htmlFor="confirm-new">确认新密码</FieldLabel>
            <Input
              id="confirm-new"
              type="password"
              autoComplete="new-password"
              value={confirmPassword}
              onChange={(event) => setConfirmPassword(event.target.value)}
            />
          </Field>
          <Button onClick={() => void changePassword()} disabled={pending}>
            {pending ? "保存中…" : "更新密码"}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>登录设备</CardTitle>
          <CardDescription>会话有效期 30 天，使用中会自动续期</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {sessions.data?.items.length ? (
            sessions.data.items.map((item) => (
              <div
                key={item.id}
                className="flex items-center justify-between gap-3 rounded-lg border border-border px-3 py-2"
              >
                <div className="min-w-0">
                  <p className="flex items-center gap-2 text-sm font-medium">
                    {item.deviceName ?? (item.kind === "web" ? "浏览器" : "桌面端")}
                    {item.current ? <Badge variant="success">当前</Badge> : null}
                  </p>
                  <p className="truncate text-xs text-muted-foreground">
                    最近使用 {formatDateTime(item.lastUsedAt)} · {item.ip ?? "未知 IP"}
                  </p>
                </div>
                {!item.current ? (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={async () => {
                      await api.revokeSession(item.id);
                      toast.success("已下线该设备");
                      void sessions.refetch();
                    }}
                  >
                    下线
                  </Button>
                ) : null}
              </div>
            ))
          ) : (
            <p className="py-4 text-center text-sm text-muted-foreground">暂无其它设备</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>退出</CardTitle>
        </CardHeader>
        <CardContent>
          <Button variant="destructive" onClick={() => void logout()}>
            <LogOut className="h-4 w-4" />
            退出登录
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}

function AboutTab() {
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>ToolBox 2.0</CardTitle>
          <CardDescription>React + Tauri + SQLite 的现代工具箱</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          <Row label="版本" value="2.0.0" />
          <Row label="前端" value="React 19 · TanStack Router · Tailwind v4" />
          <Row label="桌面端" value="Tauri 2 · Rust · WebView2" />
          <Row label="服务端" value="Fastify 5 · Drizzle ORM · SQLite" />
        </CardContent>
      </Card>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-border/60 py-2 last:border-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="truncate font-medium">{value}</span>
    </div>
  );
}