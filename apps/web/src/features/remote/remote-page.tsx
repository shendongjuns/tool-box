import * as React from "react";
import {
  Activity,
  FolderOpen,
  Plus,
  RefreshCw,
  TerminalSquare,
  Unplug,
  X,
} from "lucide-react";
import { toast } from "sonner";
import type { MonitorMetrics, Server, ServerInfo } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { isDesktop } from "@/lib/platform";
import { sshConnect, sshDisconnect, subscribeSsh } from "@/lib/ssh";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { ServerList } from "./server-list";
import { SftpPanel } from "./sftp-panel";
import { MonitorPanel } from "./monitor-panel";
import { MonitorCollector } from "./collector";
import {
  dropMonitor,
  readMonitor,
  readRefreshInterval,
  REFRESH_OPTIONS,
  saveRefreshInterval,
  writeMonitor,
  type RefreshInterval,
} from "./monitor-store";
import { TerminalView, type TerminalHandle } from "./terminal-view";
import { nextLabel, useRemoteSessions, type RemoteSession } from "./session-store";

/** 远程管理主页面。 */
export function RemotePage() {
  const api = useApi();
  const { sessions, activeId, add, remove, setActive, setTab, markDisconnected } =
    useRemoteSessions();
  const [connecting, setConnecting] = React.useState(false);
  const [pendingClose, setPendingClose] = React.useState<RemoteSession | null>(null);

  const active = sessions.find((item) => item.id === activeId) ?? null;

  /*
   * 全局只订阅一次 ssh 事件，按 sshSessionId 分发给对应终端。
   *
   * 每个 TerminalTab 各自订阅时，切换标签会卸载组件并取消订阅，
   * 重挂载前的输出全部丢失 —— 这就是「切到文件再切回来终端变空」的原因。
   */
  const writeRefs = React.useRef(new Map<string, (bytes: Uint8Array) => void>());

  React.useEffect(() => {
    let cancelled = false;
    let off: (() => void) | null = null;

    void (async () => {
      const unsubscribe = await subscribeSsh({
        onData: (sshSessionId, bytes) => {
          writeRefs.current.get(sshSessionId)?.(bytes);
        },
        onClosed: (sshSessionId) => {
          markDisconnected(sshSessionId);
        },
      });
      if (cancelled) unsubscribe();
      else off = unsubscribe;
    })();

    return () => {
      cancelled = true;
      off?.();
    };
  }, [markDisconnected]);

  const registerWriter = React.useCallback(
    (sshSessionId: string, fn: (bytes: Uint8Array) => void) => {
      writeRefs.current.set(sshSessionId, fn);
      return () => {
        writeRefs.current.delete(sshSessionId);
      };
    },
    [],
  );

  if (!isDesktop()) {
    return (
      <div className="rounded-lg border border-border bg-card px-4 py-8 text-center">
        <Unplug className="mx-auto h-8 w-8 text-muted-foreground/40" />
        <p className="mt-3 text-sm font-medium">远程管理仅在桌面端可用</p>
        <p className="mt-1 text-xs text-muted-foreground">
          浏览器无法建立 SSH 连接，请使用桌面客户端
        </p>
      </div>
    );
  }

  async function handleConnect(server: Server) {
    setConnecting(true);
    try {
      const credential = await api.getServerCredential(server.id);
      const sshSessionId = `ssh-${Date.now().toString(36)}-${Math.random()
        .toString(36)
        .slice(2, 6)}`;

      await sshConnect({
        sessionId: sshSessionId,
        host: credential.host,
        port: credential.port,
        username: credential.username,
        authType: credential.authType,
        password: credential.password ?? undefined,
        privateKey: credential.privateKey ?? undefined,
        passphrase: credential.passphrase ?? undefined,
        cols: 100,
        rows: 30,
      });

      const label = nextLabel(
        server.name,
        sessions.map((item) => item.label),
      );

      add({
        id: `tab-${Date.now().toString(36)}`,
        server,
        sshSessionId,
        label,
        tab: "terminal",
        connected: true,
      });
      toast.success(`已连接 ${server.name}`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error));
    } finally {
      setConnecting(false);
    }
  }

  async function handleClose(session: RemoteSession) {
    try {
      await sshDisconnect(session.sshSessionId);
    } catch {
      /* 忽略 */
    }
    remove(session.id);
  }

  if (sessions.length === 0) {
    return (
      <div className="space-y-4">
        <header>
          <h1 className="text-2xl font-semibold tracking-tight">服务器</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            选择服务器建立 SSH 连接，支持同时打开多个
          </p>
        </header>

        <ServerList
          activeId={null}
          onConnect={(server) => {
            if (connecting) return;
            void handleConnect(server);
          }}
        />
      </div>
    );
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2">
      {/* 会话标签栏 */}
      <div className="flex shrink-0 items-center gap-1.5 overflow-x-auto pb-1">
        {sessions.map((session) => (
          <div
            key={session.id}
            className={cn(
              "group flex min-w-[10rem] max-w-[16rem] shrink-0 items-center gap-2 rounded-md border px-3 py-2 text-xs transition-colors",
              session.id === activeId
                ? "border-primary/40 bg-primary/[0.06] font-medium text-foreground"
                : "border-border text-muted-foreground hover:bg-accent/60",
            )}
          >
            <button
              type="button"
              onClick={() => setActive(session.id)}
              className="flex min-w-0 flex-1 items-center gap-1.5"
              title={`${session.label} · ${session.server.username}@${session.server.host}:${session.server.port}`}
            >
              <span
                className={cn(
                  "h-1.5 w-1.5 shrink-0 rounded-full",
                  session.connected ? "bg-emerald-500" : "bg-red-500",
                )}
              />
              <span className="truncate">{session.label}</span>
            </button>
            <button
              type="button"
              onClick={() => setPendingClose(session)}
              title="关闭"
              className="shrink-0 rounded p-1 text-muted-foreground opacity-0 transition-opacity hover:bg-destructive/10 hover:text-destructive group-hover:opacity-100"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ))}

        <Button
          size="sm"
          variant="ghost"
          className="h-7 shrink-0 px-2 text-xs"
          onClick={() => useRemoteSessions.setState({ activeId: null })}
        >
          <Plus className="h-3 w-3" />
          新建
        </Button>
      </div>

      {!active ? (
        <div className="flex-1 overflow-y-auto">
          <ServerList
            activeId={null}
            onConnect={(server) => {
              if (connecting) return;
              void handleConnect(server);
            }}
          />
        </div>
      ) : (
        <SessionWorkspace
          session={active}
          onTabChange={(tab) => setTab(active.id, tab)}
          registerWriter={registerWriter}
        />
      )}

      {/* 关闭确认 */}
      <Dialog open={pendingClose !== null} onOpenChange={(open) => !open && setPendingClose(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>关闭这个会话？</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            将断开与 <strong className="text-foreground">{pendingClose?.label}</strong> 的连接，
            终端历史会一并丢失。
          </p>
          <DialogFooter>
            <Button size="sm" variant="ghost" onClick={() => setPendingClose(null)}>
              取消
            </Button>
            <Button
              size="sm"
              variant="destructive"
              onClick={() => {
                const target = pendingClose;
                setPendingClose(null);
                if (target) void handleClose(target);
              }}
            >
              关闭
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/*
        非活动会话的终端保持挂载（用 hidden 包裹），
        这样它们的 xterm 实例和回滚缓冲不会被销毁。
      */}
      <div className="hidden">
        {sessions
          .filter((session) => session.id !== activeId)
          .map((session) => (
            <TerminalHost
              key={session.id}
              sshSessionId={session.sshSessionId}
              registerWriter={registerWriter}
            />
          ))}
      </div>
    </div>
  );
}

/** 单个会话的工作区。 */
function SessionWorkspace({
  session,
  onTabChange,
  registerWriter,
}: {
  session: RemoteSession;
  onTabChange: (tab: RemoteSession["tab"]) => void;
  registerWriter: (sshSessionId: string, fn: (bytes: Uint8Array) => void) => () => void;
}) {
  const tabs: { id: RemoteSession["tab"]; label: string; icon: typeof TerminalSquare }[] = [
    { id: "terminal", label: "终端", icon: TerminalSquare },
    { id: "files", label: "文件", icon: FolderOpen },
    { id: "monitor", label: "监控", icon: Activity },
  ];

  /*
   * 离开「监控」时彻底关闭：停止采集（组件卸载即停）并清空缓存。
   * 仅仅切到别的会话标签则不受影响，数据留在 monitor-store 里。
   */
  const prevTab = React.useRef(session.tab);
  React.useEffect(() => {
    if (prevTab.current === "monitor" && session.tab !== "monitor") {
      dropMonitor(session.sshSessionId);
    }
    prevTab.current = session.tab;
  }, [session.tab, session.sshSessionId]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2">
      <div className="flex shrink-0 items-center justify-between gap-3">
        <div className="flex items-center gap-1 rounded-lg bg-muted/60 p-0.5">
          {tabs.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              type="button"
              onClick={() => onTabChange(id)}
              className={cn(
                "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs transition-colors",
                session.tab === id
                  ? "bg-card font-medium text-foreground shadow-sm"
                  : "text-muted-foreground hover:text-foreground",
              )}
            >
              <Icon className="h-3.5 w-3.5" />
              {label}
            </button>
          ))}
        </div>

        <p className="truncate font-mono text-xs text-muted-foreground">
          {session.server.username}@{session.server.host}:{session.server.port}
        </p>
      </div>

      {/* 终端始终挂载，切走时用 CSS 隐藏（不卸载） */}
      <div className={cn("min-h-0 flex-1", session.tab !== "terminal" && "hidden")}>
        <TerminalHost
          sshSessionId={session.sshSessionId}
          registerWriter={registerWriter}
        />
      </div>

      {session.tab === "files" ? (
        <div className="flex min-h-0 flex-1 flex-col">
          <SftpPanel sessionId={session.sshSessionId} />
        </div>
      ) : null}

      {session.tab === "monitor" ? (
        <div className="min-h-0 flex-1 overflow-y-auto">
          <MonitorTab sessionId={session.sshSessionId} />
        </div>
      ) : null}
    </div>
  );
}

/** 终端宿主：把 xterm 实例注册到全局写入表。 */
function TerminalHost({
  sshSessionId,
  registerWriter,
}: {
  sshSessionId: string;
  registerWriter: (sshSessionId: string, fn: (bytes: Uint8Array) => void) => () => void;
}) {
  const termRef = React.useRef<TerminalHandle>(null);

  React.useEffect(() => {
    return registerWriter(sshSessionId, (bytes) => {
      termRef.current?.write(bytes);
    });
  }, [sshSessionId, registerWriter]);

  return (
    <div className="h-full overflow-hidden rounded-lg border border-border bg-[#0f1115] p-2">
      <TerminalView ref={termRef} sessionId={sshSessionId} className="h-full" />
    </div>
  );
}

/** 监控标签页：按用户选择的间隔采集，支持暂停与手动刷新。 */
function MonitorTab({ sessionId }: { sessionId: string }) {
  const cached = readMonitor(sessionId);

  const [metrics, setMetrics] = React.useState<MonitorMetrics | null>(cached?.metrics ?? null);
  const [info, setInfo] = React.useState<ServerInfo | null>(cached?.info ?? null);
  const [error, setError] = React.useState<string | null>(cached?.error ?? null);
  const [loading, setLoading] = React.useState(!cached);
  const [history, setHistory] = React.useState<MonitorMetrics[]>(cached?.history ?? []);
  const [interval, setIntervalValue] = React.useState<RefreshInterval>(() =>
    readRefreshInterval(),
  );
  /** 手动刷新计数：自增即触发一次采集 */
  const [refreshTick, setRefreshTick] = React.useState(0);

  // 数据变化写回缓存，切换会话再切回来不丢
  React.useEffect(() => {
    writeMonitor(sessionId, { metrics, info, history, error });
  }, [sessionId, metrics, info, history, error]);

  const collectorRef = React.useRef<MonitorCollector | null>(null);

  React.useEffect(() => {
    if (!collectorRef.current) collectorRef.current = new MonitorCollector();
    const collector = collectorRef.current;

    let stopped = false;
    let timer: number | undefined;

    void (async () => {
      // 有缓存且非手动刷新时，直接展示缓存，不再重新采集
      const resumed = Boolean(readMonitor(sessionId)?.metrics) && refreshTick === 0;

      if (!resumed) {
        const next = await collector.collect(sessionId);
        if (stopped) return;
        if (next) {
          setMetrics(next);
          setError(null);
          setHistory((prev) => [...prev.slice(-59), next]);
        } else if (collector.lastError) {
          setError(collector.lastError);
        }
        setLoading(false);
      } else {
        await Promise.resolve();
        setLoading(false);
      }

      if (!resumed && !info) {
        setInfo(await collector.fetchServerInfo(sessionId));
      }

      // 暂停（0）时不排下一轮
      if (interval === 0) return;

      const schedule = () => {
        if (stopped) return;
        timer = window.setTimeout(() => {
          void (async () => {
            const next = await collector.collect(sessionId);
            if (stopped) return;
            if (next) {
              setMetrics(next);
              setError(null);
              setHistory((prev) => [...prev.slice(-59), next]);
            } else if (collector.lastError) {
              setError(collector.lastError);
            }
            schedule();
          })();
        }, interval);
      };
      schedule();
    })();

    return () => {
      stopped = true;
      if (timer) window.clearTimeout(timer);
    };
  }, [sessionId, interval, refreshTick, info]);

  function changeInterval(value: RefreshInterval) {
    setIntervalValue(value);
    saveRefreshInterval(value);
    // 从暂停切到自动时，立即补一次数据
    if (value !== 0) setRefreshTick((n) => n + 1);
  }

  return (
    <div className="space-y-3">
      {/* 刷新控制条 */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex items-center gap-0.5 rounded-lg bg-muted/60 p-0.5">
          {REFRESH_OPTIONS.map((option) => (
            <button
              key={option.value}
              type="button"
              onClick={() => changeInterval(option.value)}
              className={cn(
                "rounded-md px-2.5 py-1 text-[11px] transition-colors",
                interval === option.value
                  ? "bg-card font-medium text-foreground shadow-sm"
                  : "text-muted-foreground hover:text-foreground",
              )}
            >
              {option.label}
            </button>
          ))}
        </div>

        <Button
          size="sm"
          variant="ghost"
          className="h-7 px-2 text-[11px]"
          onClick={() => setRefreshTick((n) => n + 1)}
          disabled={loading}
        >
          <RefreshCw className={cn("h-3 w-3", loading && "animate-spin")} />
          手动刷新
        </Button>

        {interval === 0 ? (
          <span className="rounded-full border border-border px-2 py-0.5 text-[10px] text-muted-foreground">
            已暂停
          </span>
        ) : (
          <span className="text-[10px] text-muted-foreground">每 {interval / 1000}s 刷新</span>
        )}

        {metrics ? (
          <span className="ml-auto text-[10px] text-muted-foreground">
            最近更新 {new Date(metrics.timestamp).toLocaleTimeString("zh-CN", { hour12: false })}
          </span>
        ) : null}
      </div>

      <MonitorPanel
        metrics={metrics}
        info={info}
        loading={loading}
        error={error}
        history={history}
      />
    </div>
  );
}