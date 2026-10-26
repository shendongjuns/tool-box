import * as React from "react";
import {
  Activity,
  FolderOpen,
  Plus,
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
import { ServerList } from "./server-list";
import { SftpPanel } from "./sftp-panel";
import { MonitorPanel } from "./monitor-panel";
import { MonitorCollector } from "./collector";
import { TerminalView, type TerminalHandle } from "./terminal-view";
import { useRemoteSessions, type RemoteSession } from "./session-store";

const POLL_INTERVAL = 2000;

/** 远程管理主页面。 */
export function RemotePage() {
  const api = useApi();
  const { sessions, activeId, add, remove, setActive, setTab, markDisconnected } =
    useRemoteSessions();
  const [connecting, setConnecting] = React.useState(false);

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

      add({
        id: `tab-${Date.now().toString(36)}`,
        server,
        sshSessionId,
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
    <div className="flex h-[calc(100vh-6.5rem)] flex-col gap-2">
      {/* 会话标签栏 */}
      <div className="flex shrink-0 items-center gap-1 overflow-x-auto pb-1">
        {sessions.map((session) => (
          <div
            key={session.id}
            className={cn(
              "group flex shrink-0 items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-xs transition-colors",
              session.id === activeId
                ? "border-primary/40 bg-primary/[0.06] font-medium text-foreground"
                : "border-border text-muted-foreground hover:bg-accent/60",
            )}
          >
            <button
              type="button"
              onClick={() => setActive(session.id)}
              className="flex items-center gap-1.5"
            >
              <span
                className={cn(
                  "h-1.5 w-1.5 rounded-full",
                  session.connected ? "bg-emerald-500" : "bg-red-500",
                )}
              />
              {session.server.name}
            </button>
            <button
              type="button"
              onClick={() => void handleClose(session)}
              title="关闭"
              className="rounded p-0.5 opacity-0 transition-opacity hover:bg-destructive/10 hover:text-destructive group-hover:opacity-100"
            >
              <X className="h-3 w-3" />
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

/** 监控标签页：定时采集，保留历史用于趋势图。 */
function MonitorTab({ sessionId }: { sessionId: string }) {
  const [metrics, setMetrics] = React.useState<MonitorMetrics | null>(null);
  const [info, setInfo] = React.useState<ServerInfo | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [history, setHistory] = React.useState<MonitorMetrics[]>([]);

  React.useEffect(() => {
    const collector = new MonitorCollector();
    let stopped = false;
    let timer: number | undefined;

    void (async () => {
      setInfo(await collector.fetchServerInfo(sessionId));

      const tick = async () => {
        if (stopped) return;
        const next = await collector.collect(sessionId);
        if (stopped) return;

        if (next) {
          setMetrics(next);
          setError(null);
          // 保留最近 60 个采样点（2s × 60 = 2 分钟窗口）
          setHistory((prev) => [...prev.slice(-59), next]);
        } else if (collector.lastError) {
          setError(collector.lastError);
        }
        setLoading(false);
        timer = window.setTimeout(() => void tick(), POLL_INTERVAL);
      };

      await tick();
    })();

    return () => {
      stopped = true;
      if (timer) window.clearTimeout(timer);
    };
  }, [sessionId]);

  return (
    <MonitorPanel
      metrics={metrics}
      info={info}
      loading={loading}
      error={error}
      history={history}
    />
  );
}
