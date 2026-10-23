import * as React from "react";
import { Activity, FolderOpen, TerminalSquare, Unplug } from "lucide-react";
import { toast } from "sonner";
import type { MonitorMetrics, Server, ServerInfo } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { isDesktop } from "@/lib/platform";
import { sshConnect, sshDisconnect, subscribeSsh } from "@/lib/ssh";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ServerList } from "./server-list";
import { SftpPanel } from "./sftp-panel";
import { MonitorPanel } from "./monitor-panel";
import { MonitorCollector } from "./collector";
import { TerminalView, type TerminalHandle } from "./terminal-view";

/** 采集间隔。 */
const POLL_INTERVAL = 2000;

interface LiveSession {
  server: Server;
  sessionId: string;
}

/** 远程管理主页面。 */
export function RemotePage() {
  const api = useApi();
  const [live, setLive] = React.useState<LiveSession | null>(null);
  const [connecting, setConnecting] = React.useState(false);
  const [tab, setTab] = React.useState("terminal");

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
      // 取一次性凭据
      const credential = await api.getServerCredential(server.id);

      const sessionId = `ssh-${Date.now().toString(36)}`;
      await sshConnect({
        sessionId,
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

      setLive({ server, sessionId });
      toast.success(`已连接 ${server.name}`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error));
    } finally {
      setConnecting(false);
    }
  }

  async function handleDisconnect() {
    if (!live) return;
    try {
      await sshDisconnect(live.sessionId);
    } catch {
      /* 忽略 */
    }
    setLive(null);
    toast.success("已断开");
  }

  if (!live) {
    return (
      <div className="space-y-4">
        <header>
          <h1 className="text-2xl font-semibold tracking-tight">服务器</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            选择服务器建立 SSH 连接，即可使用终端、文件与监控
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
    <div className="flex h-[calc(100vh-7rem)] flex-col gap-3">
      <header className="flex shrink-0 flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <h1 className="truncate text-xl font-semibold tracking-tight">{live.server.name}</h1>
          <p className="truncate font-mono text-xs text-muted-foreground">
            {live.server.username}@{live.server.host}:{live.server.port}
          </p>
        </div>
        <Button size="sm" variant="outline" onClick={() => void handleDisconnect()}>
          <Unplug className="h-3.5 w-3.5" />
          断开
        </Button>
      </header>

      <Tabs value={tab} onValueChange={setTab} className="flex min-h-0 flex-1 flex-col">
        <TabsList className="w-fit shrink-0">
          <TabsTrigger value="terminal" className="gap-1.5">
            <TerminalSquare className="h-3.5 w-3.5" />
            终端
          </TabsTrigger>
          <TabsTrigger value="files" className="gap-1.5">
            <FolderOpen className="h-3.5 w-3.5" />
            文件
          </TabsTrigger>
          <TabsTrigger value="monitor" className="gap-1.5">
            <Activity className="h-3.5 w-3.5" />
            监控
          </TabsTrigger>
        </TabsList>

        <TabsContent value="terminal" className="min-h-0 flex-1">
          <TerminalTab sessionId={live.sessionId} active={tab === "terminal"} />
        </TabsContent>

        <TabsContent value="files" className="min-h-0 flex-1">
          {tab === "files" ? (
            <div className="flex h-full flex-col">
              <SftpPanel sessionId={live.sessionId} />
            </div>
          ) : null}
        </TabsContent>

        <TabsContent value="monitor" className="min-h-0 flex-1 overflow-y-auto">
          {tab === "monitor" ? <MonitorTab sessionId={live.sessionId} /> : null}
        </TabsContent>
      </Tabs>
    </div>
  );
}

/** 终端标签页：订阅输出并写入 xterm。 */
function TerminalTab({ sessionId, active }: { sessionId: string; active: boolean }) {
  const termRef = React.useRef<TerminalHandle>(null);

  React.useEffect(() => {
    let cancelled = false;
    let unsubscribe: (() => void) | null = null;

    void (async () => {
      const off = await subscribeSsh({
        onData: (id, bytes) => {
          if (id === sessionId) termRef.current?.write(bytes);
        },
        onClosed: (id) => {
          if (id === sessionId) {
            termRef.current?.writeln("\r\n\x1b[33m[连接已关闭]\x1b[0m");
          }
        },
      });
      if (cancelled) off();
      else unsubscribe = off;
    })();

    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, [sessionId]);

  React.useEffect(() => {
    if (active) termRef.current?.focus();
  }, [active]);

  return (
    <div className="h-full overflow-hidden rounded-lg border border-border bg-[#0f1115] p-2">
      <TerminalView ref={termRef} sessionId={sessionId} className="h-full" />
    </div>
  );
}

/** 监控标签页：定时采集。 */
function MonitorTab({ sessionId }: { sessionId: string }) {
  const [metrics, setMetrics] = React.useState<MonitorMetrics | null>(null);
  const [info, setInfo] = React.useState<ServerInfo | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [loading, setLoading] = React.useState(true);

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
    <MonitorPanel metrics={metrics} info={info} loading={loading} error={error} />
  );
}