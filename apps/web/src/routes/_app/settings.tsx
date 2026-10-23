import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { z } from "zod";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Cloud, Database, LogOut, Monitor, Moon, Palette, Plus, Sun } from "lucide-react";
import { toast } from "sonner";
import type { Accent, ThemeMode } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { useAuth } from "@/lib/auth-session";
import { queryKeys, useCurrentSourceKey, useSettingsQuery } from "@/lib/hooks";
import { logoutCurrent, switchDataSource } from "@/lib/session";
import { useDataSource } from "@/lib/data-source";
import { isDesktop } from "@/lib/platform";
import { useTheme } from "@/lib/theme";
import { cn, formatDateTime } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { LatencyBadge } from "@/components/latency-badge";
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
        <p className="mt-1 text-sm text-muted-foreground">外观、数据源与账户</p>
      </header>

      <Tabs
        value={tab}
        onValueChange={(value) =>
          void navigate({ to: "/settings", search: { tab: value as SettingsTab } })
        }
      >
        {/* 窄屏允许换行，避免四个标签挤成一行被裁切 */}
        <TabsList className="flex-wrap">
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
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();
  const settings = useSettingsQuery();

  const saveSetting = useMutation({
    mutationFn: (values: Record<string, string | number | boolean>) => api.putSettings({ values }),
    onSuccess: () => {
      toast.success("设置已保存");
      void queryClient.invalidateQueries({ queryKey: queryKeys.settings(sourceKey) });
    },
  });


  return (
    <div className="space-y-4">
      <DataSourceCard />
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
                <p className="text-xs text-muted-foreground">
                  始终隐藏到系统托盘；彻底退出请使用托盘右键菜单。
                </p>
              </div>
              <Badge variant="secondary">托盘</Badge>
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
    if (newPassword.length === 0) {
      toast.error("新密码不能为空");
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
    await logoutCurrent();
    await navigate({ to: "/login", replace: true });
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
            <FieldHint>长度与字符不限</FieldHint>
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

/**
 * 数据源管理：本地 + 用户自建的多个云端地址。
 *
 * 页面本身不区分数据源；这里只管理「连到哪儿」，切换后统一退回登录页。
 */
function DataSourceCard() {
  const { cloudSources, activeId, label } = useDataSource();
  const navigate = useNavigate();
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [pendingRemove, setPendingRemove] = useState<{ id: string; name: string } | null>(null);
  const [draft, setDraft] = useState<{ id: string | null; name: string; url: string } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const addCloud = useDataSource((state) => state.addCloud);
  const updateCloud = useDataSource((state) => state.updateCloud);
  const removeCloud = useDataSource((state) => state.removeCloud);

  /** 切换数据源：这是唯一会退出登录的操作。 */
  async function pick(id: string, name: string) {
    if (id === activeId) return;
    setPendingId(id);
    await switchDataSource(id);
    toast.success(`已切换到 ${name}，请重新登录`);
    await navigate({ to: "/login", replace: true });
  }

  /** 保存：只写列表，不切换、不退出登录。 */
  function save() {
    if (!draft) return;
    const name = draft.name.trim();
    const url = draft.url.trim();
    if (name.length === 0) return setError("请填写名称");

    let parsed: URL;
    try {
      parsed = new URL(url);
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") throw new Error("bad");
    } catch {
      return setError("地址格式不正确，例如 http://192.168.1.10:3000");
    }
    void parsed;

    if (draft.id) {
      updateCloud(draft.id, { name, url });
      toast.success("已保存");
    } else {
      const normalized = url.replace(/\/$/, "");
      if (cloudSources.some((item) => item.url === normalized)) {
        return setError("这个地址已经在列表里了");
      }
      addCloud({ name, url });
      toast.success("已添加，点「使用」即可切换");
    }
    setDraft(null);
    setError(null);
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Database className="h-4 w-4 text-primary" />
          数据源
        </CardTitle>
        <CardDescription>
          当前：{label}。不同数据源之间数据完全独立。
          <strong className="font-medium text-foreground">保存不会切换</strong>
          ，点「使用」才会切走并重新登录。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex items-center gap-3 rounded-lg border border-primary/40 bg-primary/5 px-3 py-2.5">
          <div className="grid h-8 w-8 place-items-center rounded-lg bg-primary text-primary-foreground">
            {activeId === "local" ? (
              <Database className="h-4 w-4" />
            ) : (
              <Cloud className="h-4 w-4" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{label}</p>
            <p className="text-xs text-muted-foreground">正在使用</p>
          </div>
          <Badge variant="success">当前</Badge>
        </div>

        <div className="space-y-2 pt-2">
          <p className="text-xs font-medium text-muted-foreground">全部数据源</p>

          {activeId !== "local" ? (
            <SwitchRow
              icon={<Database className="h-4 w-4" />}
              name="本地数据"
              note="这台电脑"
              busy={pendingId === "local"}
              onClick={() => void pick("local", "本地数据")}
            />
          ) : null}

          {cloudSources.map((source) => (
            <SwitchRow
              key={source.id}
              icon={<Cloud className="h-4 w-4" />}
              name={source.name}
              note={source.url}
              latencyUrl={source.url}
              busy={pendingId === source.id}
              active={source.id === activeId}
              onClick={() => void pick(source.id, source.name)}
              onEdit={() => {
                setDraft({ id: source.id, name: source.name, url: source.url });
                setError(null);
              }}
              onRemove={source.id === activeId ? undefined : () => setPendingRemove(source)}
            />
          ))}

          {draft ? (
            <div className="space-y-2 rounded-lg border border-border p-3">
              <Field>
                <FieldLabel htmlFor="new-name">名称</FieldLabel>
                <Input
                  id="new-name"
                  value={draft.name}
                  onChange={(event) => setDraft({ ...draft, name: event.target.value })}
                  placeholder="例如：公司服务器"
                  autoFocus
                />
              </Field>
              <Field>
                <FieldLabel htmlFor="new-url">服务器地址</FieldLabel>
                <Input
                  id="new-url"
                  value={draft.url}
                  onChange={(event) => setDraft({ ...draft, url: event.target.value })}
                  placeholder="http://192.168.1.10:3000"
                  className="font-mono"
                />
                {error ? (
                  <p className="text-xs text-destructive">{error}</p>
                ) : (
                  <FieldHint>保存后不会自动切换，需要点「使用」。</FieldHint>
                )}
              </Field>
              <div className="flex gap-2">
                <Button onClick={save}>保存</Button>
                <Button
                  variant="outline"
                  onClick={() => {
                    setDraft(null);
                    setError(null);
                  }}
                >
                  取消
                </Button>
              </div>
            </div>
          ) : (
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setDraft({ id: null, name: "", url: "" });
                setError(null);
              }}
            >
              <Plus className="h-4 w-4" />
              添加云端服务器
            </Button>
          )}
        </div>
      </CardContent>

      <ConfirmDialog
        open={pendingRemove !== null}
        title="移除这个数据源？"
        description={
          <>
            只是从本机列表移除 <strong>{pendingRemove?.name}</strong>，不会删除服务器上的数据。
            之后可以重新添加。
          </>
        }
        confirmText="移除"
        destructive
        onConfirm={() => {
          if (pendingRemove) {
            removeCloud(pendingRemove.id);
            toast.success(`已移除 ${pendingRemove.name}`);
            setPendingRemove(null);
          }
        }}
        onCancel={() => setPendingRemove(null)}
      />
    </Card>
  );
}

/** 轻量确认弹框（带「记住选择」不适用，用于破坏性操作二次确认）。 */
function ConfirmDialog({
  open,
  title,
  description,
  confirmText,
  destructive = false,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  title: string;
  description: React.ReactNode;
  confirmText: string;
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="w-full max-w-sm rounded-xl border border-border bg-card p-5 shadow-xl">
        <h3 className="text-base font-semibold">{title}</h3>
        <p className="mt-1.5 text-sm text-muted-foreground">{description}</p>
        <div className="mt-5 flex justify-end gap-2">
          <Button variant="outline" size="sm" onClick={onCancel}>
            取消
          </Button>
          <Button
            size="sm"
            variant={destructive ? "destructive" : "default"}
            onClick={onConfirm}
          >
            {confirmText}
          </Button>
        </div>
      </div>
    </div>
  );
}

function SwitchRow({
  icon,
  name,
  note,
  latencyUrl,
  busy,
  active = false,
  onClick,
  onEdit,
  onRemove,
}: {
  icon: React.ReactNode;
  name: string;
  note: string;
  latencyUrl?: string;
  busy: boolean;
  active?: boolean;
  onClick: () => void;
  onEdit?: () => void;
  onRemove?: () => void;
}) {
  return (
    <div
      className={cn(
        "flex items-center gap-3 rounded-lg border px-3 py-2",
        active ? "border-primary/30 bg-primary/[0.03]" : "border-border",
      )}
    >
      <div className="grid h-8 w-8 place-items-center rounded-lg bg-muted text-muted-foreground">
        {icon}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <p className="truncate text-sm font-medium">{name}</p>
          {latencyUrl ? <LatencyBadge url={latencyUrl} /> : null}
        </div>
        <p className="truncate text-xs text-muted-foreground">{note}</p>
      </div>

      {onEdit ? (
        <Button variant="ghost" size="sm" onClick={onEdit}>
          编辑
        </Button>
      ) : null}

      {active ? (
        <Badge variant="secondary">使用中</Badge>
      ) : (
        <Button variant="ghost" size="sm" disabled={busy} onClick={onClick}>
          {busy ? "切换中…" : "使用"}
        </Button>
      )}

      {onRemove ? (
        <Button variant="ghost" size="sm" onClick={onRemove} className="text-destructive">
          删除
        </Button>
      ) : null}
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