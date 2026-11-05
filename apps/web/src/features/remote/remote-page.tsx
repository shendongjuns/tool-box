import * as React from "react";
import { Activity, FolderOpen, Plus, RefreshCw, TerminalSquare, Unplug, X } from "lucide-react";
import { toast } from "sonner";
import type { MonitorMetrics, Server, ServerInfo } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { isDesktop } from "@/lib/platform";
import {
  getKnownHost,
  getKnownHostsPath,
  sshConnect,
  sshDisconnect,
  subscribeSsh,
  trustKnownHost,
} from "@/lib/ssh";
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
  notifyMonitor,
  saveRefreshInterval,
  startMonitor,
  subscribeMonitor,
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

      const knownHostsPath = (await getKnownHostsPath()) ?? undefined;

      const connectOnce = (trustNewHost: boolean) =>
        sshConnect({
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
          knownHostsPath,
          trustNewHost,
        });

      try {
        await connectOnce(false);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);

        /*
         * 主机密钥变化：可能是服务器重装，也可能是中间人攻击。
         * 不自动信任，交给用户显式决定 —— 这是 TOFU 的核心。
         */
        if (!message.includes("主机密钥") && !message.includes("HOST_KEY")) {
          throw error;
        }

        const confirmed = window.confirm(
          `${credential.host}:${credential.port} 的主机密钥与上次记录不一致。\n\n` +
            "可能是服务器重装或更换，也可能是中间人攻击。\n" +
            "确认信任新指纹并继续连接吗？",
        );
        if (!confirmed) {
          throw new Error("已取消连接：主机密钥校验未通过");
        }

        // 拉取当前指纹并显式信任
        try {
          const observed = await getKnownHost(credential.host, credential.port);
          if (observed) {
            await trustKnownHost(
              credential.host,
              credential.port,
              observed.algorithm,
              observed.fingerprint,
            );
          }
        } catch {
          /* 拿不到就靠 trustNewHost 覆盖 */
        }

        await connectOnce(true);
      }

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
    // 会话关闭才真正停止监控并丢弃缓存
    dropMonitor(session.sshSessionId);
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
          /*
           * 整个标签就是一个按钮。
           *
           * 之前外层是 div（带边框背景，看起来像按钮），
           * 但 onClick 只挂在内层文字按钮上 ——
           * 点在 padding（px-3 py-2 = 12px/8px）区域没有任何反应，
           * 用户感受就是「按钮变大了但边缘点不动」。
           * 现在把点击区域铺满整个标签，关闭按钮用 stopPropagation 隔离。
           */
          <div
            key={session.id}
            onClick={() => setActive(session.id)}
            role="button"
            // 自定义 role 会覆盖语义，屏幕阅读器只能靠 aria-label 知道这是什么
            aria-label={`切换到会话 ${session.label}`}
            aria-current={session.id === activeId ? "true" : undefined}
            tabIndex={0}
            onKeyDown={(event) => {
              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                setActive(session.id);
              }
            }}
            className={cn(
              "group flex min-w-[10rem] max-w-[16rem] shrink-0 cursor-pointer items-center gap-2 rounded-md border px-3 py-2 text-xs transition-colors",
              session.id === activeId
                ? "border-primary/40 bg-primary/[0.06] font-medium text-foreground"
                : "border-border text-muted-foreground hover:bg-accent/60",
            )}
            title={`${session.label} · ${session.server.username}@${session.server.host}:${session.server.port}`}
          >
            <span
              className={cn(
                "h-1.5 w-1.5 shrink-0 rounded-full",
                session.connected ? "bg-emerald-500" : "bg-red-500",
              )}
            />
            <span className="min-w-0 flex-1 truncate">{session.label}</span>
            <button
              type="button"
              onClick={(event) => {
                // 阻止冒泡，否则点关闭会先触发切换
                event.stopPropagation();
                setPendingClose(session);
              }}
              title="关闭"
              aria-label={`关闭会话 ${session.label}`}
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
        // key 必须绑定会话 id。
        // 否则切换标签时 React 复用同一个 SessionWorkspace 实例，
        // 内部的 MonitorTab 仍持有旧 sessionId 的采集循环，
        // 表现为「切了标签但监控画面没变」。
        <SessionWorkspace
          key={active.id}
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
        <TerminalHost sshSessionId={session.sshSessionId} registerWriter={registerWriter} />
      </div>

      {session.tab === "files" ? (
        <div className="flex min-h-0 flex-1 flex-col">
          <SftpPanel sessionId={session.sshSessionId} />
        </div>
      ) : null}

      {/*
        监控常驻挂载（与终端同理）。
        切到「终端 / 文件」只是隐藏，采集任务继续跑 ——
        否则切回来会从零开始，且历史上的曲线会断。
        真正停止只发生在会话关闭时（handleClose 里 dropMonitor）。
      */}
      <div
        className={cn(
          /*
           * overflow-x-hidden：监控面板内部有大量图表，
           * 任何元素偶然溢出都会立刻撑出横向滚动条 ——
           * 滚动条本身占据宽度，触发 ResizeObserver，图表重排，
           * 表现为「鼠标一划画面抖一下」。
           * 这里直接禁掉横向滚动，纵向保留。
           *
           * scrollbar-gutter: stable：给滚动条预留固定空间，
           * 内容从「不需要滚动」变成「需要滚动」时宽度不会突变。
           */
          "min-h-0 flex-1 overflow-y-auto overflow-x-hidden [scrollbar-gutter:stable]",
          session.tab !== "monitor" && "hidden",
        )}
      >
        <MonitorTab sessionId={session.sshSessionId} />
      </div>
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

/**
 * 监控标签页。
 *
 * 只负责「读 store 快照 + 触发采集配置」，定时器在 monitor-store 里，
 * 因此切到终端/文件或切走会话都不会停止后台记录。
 */
function MonitorTab({ sessionId }: { sessionId: string }) {
  /*
   * 组件状态只是 store 的「镜像」。
   *
   * 唯一写入方是后台引擎（写 cache 后 notifyMonitor）；
   * 组件只读，不反向覆盖 —— 否则切走再切回时，
   * 组件里过期的 state 会把后台刚采到的新数据冲掉。
   */
  const cached = readMonitor(sessionId);

  const [metrics, setMetrics] = React.useState<MonitorMetrics | null>(cached?.metrics ?? null);
  const [info, setInfo] = React.useState<ServerInfo | null>(cached?.info ?? null);
  const [error, setError] = React.useState<string | null>(cached?.error ?? null);
  const [loading, setLoading] = React.useState(!cached?.metrics);
  const [history, setHistory] = React.useState<MonitorMetrics[]>(cached?.history ?? []);
  const [interval, setIntervalValue] = React.useState<RefreshInterval>(() => readRefreshInterval());

  /** 从 store 同步到组件 state（单向） */
  const syncFromStore = React.useCallback(() => {
    const snapshot = readMonitor(sessionId);
    if (!snapshot) return;
    setMetrics(snapshot.metrics);
    setInfo(snapshot.info);
    setHistory(snapshot.history);
    setError(snapshot.error);
    if (snapshot.metrics) setLoading(false);
  }, [sessionId]);

  // 订阅后台引擎的更新
  React.useEffect(() => {
    return subscribeMonitor((changedId) => {
      if (changedId === sessionId) syncFromStore();
    });
  }, [sessionId, syncFromStore]);

  // 启动/更新后台采集（引擎本身不随组件卸载停止）
  React.useEffect(() => {
    const collector = collectorFor(sessionId);

    const runOnce = async () => {
      // 首次先取一次服务器信息
      const before = readMonitor(sessionId);
      if (!before?.info) {
        const serverInfo = await collector.fetchServerInfo(sessionId);
        const current = readMonitor(sessionId) ?? {
          metrics: null,
          info: null,
          history: [],
          error: null,
        };
        writeMonitor(sessionId, { ...current, info: serverInfo });
      }

      const next = await collector.collect(sessionId);
      const current = readMonitor(sessionId) ?? {
        metrics: null,
        info: null,
        history: [],
        error: null,
      };

      if (next) {
        writeMonitor(sessionId, {
          ...current,
          metrics: next,
          history: [...current.history.slice(-59), next],
          error: null,
        });
      } else if (collector.lastError) {
        writeMonitor(sessionId, { ...current, error: collector.lastError });
      }

      notifyMonitor(sessionId);
    };

    startMonitor(sessionId, interval, runOnce);
  }, [sessionId, interval]);

  function changeInterval(value: RefreshInterval) {
    setIntervalValue(value);
    saveRefreshInterval(value);
  }

  return (
    <div className="space-y-3">
      {/*
        刷新控制条固定在顶部。
        
        用 sticky 而不是把控制条提到滚动容器外面 ——
        后者需要重构 MonitorTab 的层级，而 sticky 只需一个类。
        top-0 + z-index 保证它盖住滚动上来的图表；
        bg 必须不透明，否则内容会从下面透出来。
      */}
      <div className="sticky top-0 z-20 -mx-1 flex flex-wrap items-center gap-2 bg-background/95 px-1 py-1.5 backdrop-blur">
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
          onClick={() => {
            // 手动刷新：立即触发一次（不改变后台节奏）
            const collector = collectorFor(sessionId);
            void (async () => {
              const next = await collector.collect(sessionId);
              const current = readMonitor(sessionId);
              if (!current) return;
              if (next) {
                writeMonitor(sessionId, {
                  ...current,
                  metrics: next,
                  history: [...current.history.slice(-59), next],
                  error: null,
                });
              }
              notifyMonitor(sessionId);
            })();
          }}
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

/** 每个会话复用同一个 collector（保留 CPU/网络的采样基线）。 */
const collectors = new Map<string, MonitorCollector>();

function collectorFor(sessionId: string): MonitorCollector {
  const existing = collectors.get(sessionId);
  if (existing) return existing;
  const created = new MonitorCollector();
  collectors.set(sessionId, created);
  return created;
}
