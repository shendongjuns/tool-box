import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { z } from "zod";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Cloud, Database, LogOut, Monitor, Moon, Palette, Pencil, Plus, Sun, Trash2 } from "lucide-react";
import { toast } from "sonner";
import type { Accent, ThemeMode } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { useAuth } from "@/lib/auth-session";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { logoutCurrent, reloadsOnSwitch, switchDataSource } from "@/lib/session";
import { useDataSource } from "@/lib/data-source";
import { useTheme } from "@/lib/theme";
import { cn, formatDateTime } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { LatencyBadge } from "@/components/latency-badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
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
  return (
    <div className="space-y-4">
      <DataSourceCard />
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
          <div className="grid gap-3 sm:grid-cols-2">
            <Field>
              <FieldLabel htmlFor="new">新密码</FieldLabel>
              <Input
                id="new"
                type="password"
                autoComplete="new-password"
                value={newPassword}
                onChange={(event) => setNewPassword(event.target.value)}
              />
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
          </div>
          <div className="flex justify-end">
            <Button size="sm" onClick={() => void changePassword()} disabled={pending}>
              {pending ? "保存中…" : "更新密码"}
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>登录设备</CardTitle>
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
  const { cloudSources, activeId } = useDataSource();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [draft, setDraft] = useState<{ id: string | null; name: string; url: string } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const addCloud = useDataSource((state) => state.addCloud);
  const updateCloud = useDataSource((state) => state.updateCloud);
  const removeCloud = useDataSource((state) => state.removeCloud);

  async function pick(id: string, name: string) {
    if (id === activeId) return;
    setPendingId(id);
    await switchDataSource(id);
    if (reloadsOnSwitch()) return;
    await queryClient.cancelQueries();
    queryClient.clear();
    toast.success(`已切换到 ${name}`);
    await navigate({ to: "/login", replace: true });
  }

  function save() {
    if (!draft) return;
    const name = draft.name.trim();
    const url = draft.url.trim();
    if (!name) return setError("请填写名称");

    try {
      const parsed = new URL(url);
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") throw new Error("bad");
    } catch {
      return setError("地址格式不正确");
    }

    if (draft.id) {
      updateCloud(draft.id, { name, url });
      toast.success("已保存");
    } else {
      if (cloudSources.some((item) => item.url === url.replace(/\/$/, ""))) {
        return setError("该地址已存在");
      }
      addCloud({ name, url });
      toast.success("已添加");
    }
    setDraft(null);
    setError(null);
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">数据源</CardTitle>
      </CardHeader>

      <CardContent className="p-0">
        <div className="divide-y divide-border border-y border-border">
          <SourceLine
            active={activeId === "local"}
            icon={Database}
            name="本地数据"
            note="这台电脑"
            busy={pendingId === "local"}
            onPick={() => void pick("local", "本地数据")}
          />
          {cloudSources.map((source) => (
            <SourceLine
              key={source.id}
              active={source.id === activeId}
              icon={Cloud}
              name={source.name}
              note={source.url}
              latencyUrl={source.url}
              busy={pendingId === source.id}
              onPick={() => void pick(source.id, source.name)}
              onEdit={() => {
                setDraft({ id: source.id, name: source.name, url: source.url });
                setError(null);
              }}
              onRemove={
                source.id === activeId
                  ? undefined
                  : () => {
                      removeCloud(source.id);
                      toast.success("已移除");
                    }
              }
            />
          ))}
        </div>

        {draft ? (
          <div className="space-y-3 p-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <Field>
                <FieldLabel htmlFor="ds-name">名称</FieldLabel>
                <Input
                  id="ds-name"
                  value={draft.name}
                  onChange={(event) => setDraft({ ...draft, name: event.target.value })}
                  placeholder="公司服务器"
                  autoFocus
                />
              </Field>
              <Field>
                <FieldLabel htmlFor="ds-url">地址</FieldLabel>
                <Input
                  id="ds-url"
                  value={draft.url}
                  onChange={(event) => setDraft({ ...draft, url: event.target.value })}
                  placeholder="http://10.0.0.2:7788"
                  className="font-mono text-xs"
                />
              </Field>
            </div>
            {error ? <FieldError>{error}</FieldError> : null}
            <div className="flex justify-end gap-2">
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  setDraft(null);
                  setError(null);
                }}
              >
                取消
              </Button>
              <Button size="sm" onClick={save}>
                保存
              </Button>
            </div>
          </div>
        ) : (
          <div className="p-2">
            <Button
              size="sm"
              variant="ghost"
              className="w-full justify-start text-muted-foreground"
              onClick={() => {
                setDraft({ id: null, name: "", url: "" });
                setError(null);
              }}
            >
              <Plus className="h-3.5 w-3.5" />
              添加云端服务器
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

/** 数据源行：与登录页保持同一套视觉。 */
function SourceLine({
  active,
  icon: Icon,
  name,
  note,
  latencyUrl,
  busy,
  onPick,
  onEdit,
  onRemove,
}: {
  active: boolean;
  icon: React.ComponentType<{ className?: string }>;
  name: string;
  note: string;
  latencyUrl?: string;
  busy?: boolean;
  onPick: () => void;
  onEdit?: () => void;
  onRemove?: () => void;
}) {
  return (
    <div className={cn("group flex items-center gap-3 px-4 py-2.5", active && "bg-primary/[0.04]")}>
      <span
        className={cn(
          "grid h-8 w-8 shrink-0 place-items-center rounded-md",
          active ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground",
        )}
      >
        <Icon className="h-4 w-4" />
      </span>

      <button
        type="button"
        onClick={onPick}
        disabled={active || busy}
        className="min-w-0 flex-1 text-left disabled:cursor-default"
      >
        <span className="flex items-center gap-1.5">
          <span className="truncate text-sm font-medium">{name}</span>
          {latencyUrl ? <LatencyBadge url={latencyUrl} /> : null}
        </span>
        <span className="mt-0.5 block truncate text-xs text-muted-foreground">{note}</span>
      </button>

      {active ? (
        <span className="flex shrink-0 items-center gap-1 text-xs font-medium text-primary">
          <Check className="h-3.5 w-3.5" />
          当前
        </span>
      ) : busy ? (
        <span className="shrink-0 text-xs text-muted-foreground">切换中…</span>
      ) : (
        <span className="flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
          {onEdit ? (
            <button
              type="button"
              onClick={onEdit}
              title="编辑"
              className="rounded p-1.5 text-muted-foreground hover:bg-accent hover:text-foreground"
            >
              <Pencil className="h-3.5 w-3.5" />
            </button>
          ) : null}
          {onRemove ? (
            <button
              type="button"
              onClick={onRemove}
              title="移除"
              className="rounded p-1.5 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
            >
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          ) : null}
        </span>
      )}
    </div>
  );
}


function AboutTab() {
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>ToolBox 2.0.0</CardTitle>
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