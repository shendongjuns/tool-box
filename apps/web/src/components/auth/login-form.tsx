import * as React from "react";
import { Eye, EyeOff, Loader2 } from "lucide-react";
import type { DataSource } from "@/lib/platform";
import { DATA_SOURCES } from "@/lib/source";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field, FieldError, FieldHint, FieldLabel } from "@/components/ui/field";

export interface LoginFormValues {
  username: string;
  password: string;
  confirmPassword?: string;
  setupToken?: string;
}

export function LoginForm({
  source,
  initialized,
  disabled = false,
  onSubmit,
  extra,
}: {
  source: DataSource;
  initialized: boolean;
  /** 服务器不可达时禁用提交，避免用户对着按钮反复点 */
  disabled?: boolean;
  onSubmit: (values: LoginFormValues) => Promise<void>;
  extra?: React.ReactNode;
}) {
  const [username, setUsername] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [confirmPassword, setConfirmPassword] = React.useState("");
  const [setupToken, setSetupToken] = React.useState("");
  const [showPassword, setShowPassword] = React.useState(false);
  const [pending, setPending] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const isSetup = !initialized;
  const passwordTooShort = password.length > 0 && password.length < 10;
  const mismatch = isSetup && confirmPassword.length > 0 && password !== confirmPassword;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);

    if (isSetup) {
      if (password.length < 10) {
        setError("密码至少需要 10 个字符");
        return;
      }
      if (password !== confirmPassword) {
        setError("两次输入的密码不一致");
        return;
      }
    }

    setPending(true);
    try {
      await onSubmit({
        username: username.trim(),
        password,
        ...(isSetup ? { confirmPassword, setupToken: setupToken.trim() } : {}),
      });
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : "操作失败，请稍后重试");
    } finally {
      setPending(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5" noValidate>
      <Field>
        <FieldLabel htmlFor="username">用户名</FieldLabel>
        <Input
          id="username"
          autoFocus
          autoComplete="username"
          value={username}
          onChange={(event) => setUsername(event.target.value)}
          placeholder={isSetup ? "给自己起一个名字" : "输入用户名"}
          required
        />
      </Field>

      <Field>
        <FieldLabel htmlFor="password">密码</FieldLabel>
        <div className="relative">
          <Input
            id="password"
            type={showPassword ? "text" : "password"}
            autoComplete={isSetup ? "new-password" : "current-password"}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder={isSetup ? "至少 10 个字符" : "输入密码"}
            required
            className="pr-10"
          />
          <button
            type="button"
            onClick={() => setShowPassword((value) => !value)}
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-muted-foreground transition-colors hover:text-foreground"
            aria-label={showPassword ? "隐藏密码" : "显示密码"}
          >
            {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </button>
        </div>
        {isSetup ? <FieldHint>建议使用大小写字母、数字与符号的组合。</FieldHint> : null}
        {passwordTooShort ? <FieldError>还差 {10 - password.length} 个字符。</FieldError> : null}
      </Field>

      {isSetup ? (
        <Field>
          <FieldLabel htmlFor="confirm">确认密码</FieldLabel>
          <Input
            id="confirm"
            type={showPassword ? "text" : "password"}
            autoComplete="new-password"
            value={confirmPassword}
            onChange={(event) => setConfirmPassword(event.target.value)}
            placeholder="再输入一次"
            required
          />
          {mismatch ? <FieldError>两次输入的密码不一致</FieldError> : null}
        </Field>
      ) : null}

      {isSetup && source === "cloud" ? (
        <Field>
          <FieldLabel htmlFor="setup-token">初始化口令（可选）</FieldLabel>
          <Input
            id="setup-token"
            value={setupToken}
            onChange={(event) => setSetupToken(event.target.value)}
            placeholder="服务器要求时填写"
          />
          <FieldHint>部署时设置了 SETUP_TOKEN 才需要填写。</FieldHint>
        </Field>
      ) : null}

      {extra}

      {error ? (
        <p className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
          {error}
        </p>
      ) : null}

      <Button type="submit" className="w-full" size="lg" disabled={pending || disabled}>
        {pending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
        {pending ? "请稍候…" : isSetup ? "创建账号并进入" : "登录"}
      </Button>

      <p className="text-center text-xs text-muted-foreground">
        {DATA_SOURCES[source].description}
      </p>
    </form>
  );
}
