import * as React from "react";
import { toast } from "sonner";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import type { Server } from "@toolbox/contracts";
import { useApi } from "@/lib/api-context";
import { queryKeys, useCurrentSourceKey } from "@/lib/hooks";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

const DEFAULT_PORT = 22;

/** 新增 / 编辑服务器。 */
export function ServerFormDialog({
  open,
  server,
  onClose,
}: {
  open: boolean;
  server: Server | null;
  onClose: () => void;
}) {
  const api = useApi();
  const queryClient = useQueryClient();
  const sourceKey = useCurrentSourceKey();

  const [name, setName] = React.useState(server?.name ?? "");
  const [host, setHost] = React.useState(server?.host ?? "");
  const [port, setPort] = React.useState(String(server?.port ?? DEFAULT_PORT));
  const [username, setUsername] = React.useState(server?.username ?? "");
  const [authType, setAuthType] = React.useState<"password" | "key">(
    server?.authType ?? "password",
  );
  const [password, setPassword] = React.useState("");
  const [privateKey, setPrivateKey] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);

  const save = useMutation({
    mutationFn: async () => {
      const payload = {
        name: name.trim(),
        host: host.trim(),
        port: Number(port) || DEFAULT_PORT,
        username: username.trim(),
        authType,
        // 编辑时留空表示不修改凭据
        ...(password ? { password } : {}),
        ...(privateKey ? { privateKey } : {}),
      };

      if (server) return api.updateServer(server.id, payload);
      return api.createServer(payload);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: queryKeys.servers(sourceKey) });
      toast.success(server ? "已保存" : "已添加");
      onClose();
    },
    onError: (err: unknown) => {
      setError(err instanceof Error ? err.message : "保存失败");
    },
  });

  function submit() {
    setError(null);
    if (!name.trim()) return setError("请填写名称");
    if (!host.trim()) return setError("请填写主机地址");
    if (!username.trim()) return setError("请填写用户名");
    if (!server && authType === "password" && !password) {
      return setError("请填写密码");
    }
    if (!server && authType === "key" && !privateKey.trim()) {
      return setError("请粘贴私钥内容");
    }
    save.mutate();
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{server ? "编辑服务器" : "添加服务器"}</DialogTitle>
        </DialogHeader>

        <div className="space-y-3">
          <Field>
            <FieldLabel htmlFor="srv-name">名称</FieldLabel>
            <Input
              id="srv-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="生产环境"
              autoFocus
            />
          </Field>

          <div className="grid gap-3 sm:grid-cols-[1fr_5.5rem]">
            <Field>
              <FieldLabel htmlFor="srv-host">主机</FieldLabel>
              <Input
                id="srv-host"
                value={host}
                onChange={(event) => setHost(event.target.value)}
                placeholder="192.168.1.10"
                className="font-mono text-xs"
              />
            </Field>
            <Field>
              <FieldLabel htmlFor="srv-port">端口</FieldLabel>
              <Input
                id="srv-port"
                value={port}
                onChange={(event) => setPort(event.target.value)}
                className="font-mono text-xs"
              />
            </Field>
          </div>

          <Field>
            <FieldLabel htmlFor="srv-user">用户名</FieldLabel>
            <Input
              id="srv-user"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              placeholder="root"
              className="font-mono text-xs"
            />
          </Field>

          <Field>
            <FieldLabel>认证方式</FieldLabel>
            <div className="flex gap-2">
              {(["password", "key"] as const).map((type) => (
                <button
                  key={type}
                  type="button"
                  onClick={() => setAuthType(type)}
                  className={
                    "flex-1 rounded-md border px-3 py-1.5 text-xs transition-colors " +
                    (authType === type
                      ? "border-primary/40 bg-primary/5 font-medium text-primary"
                      : "border-border text-muted-foreground hover:bg-accent")
                  }
                >
                  {type === "password" ? "密码" : "私钥"}
                </button>
              ))}
            </div>
          </Field>

          {authType === "password" ? (
            <Field>
              <FieldLabel htmlFor="srv-pass">
                密码{server ? "（留空不修改）" : ""}
              </FieldLabel>
              <Input
                id="srv-pass"
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoComplete="new-password"
              />
            </Field>
          ) : (
            <Field>
              <FieldLabel htmlFor="srv-key">
                私钥{server ? "（留空不修改）" : ""}
              </FieldLabel>
              <textarea
                id="srv-key"
                value={privateKey}
                onChange={(event) => setPrivateKey(event.target.value)}
                placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"
                rows={4}
                className="w-full rounded-lg border border-input bg-[var(--card)] px-3 py-2 font-mono text-xs focus-visible:border-[var(--ring)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ring)]/30"
              />
            </Field>
          )}

          {error ? <FieldError>{error}</FieldError> : null}
        </div>

        <DialogFooter>
          <Button variant="ghost" size="sm" onClick={onClose}>
            取消
          </Button>
          <Button size="sm" onClick={submit} disabled={save.isPending}>
            {save.isPending ? "保存中…" : "保存"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}