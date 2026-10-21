import { useEffect } from "react";
import type { Accent, ThemeMode } from "@toolbox/contracts";
import { useTheme } from "./theme";

const MODES: ThemeMode[] = ["light", "dark", "system"];
const ACCENTS: Accent[] = ["indigo", "violet", "emerald", "amber", "rose", "slate"];

/** 把服务端保存的外观设置应用到本地主题（不额外发请求）。 */
export function applyRemoteTheme(
  values: Record<string, string | number | boolean> | undefined,
): void {
  if (!values) return;
  const { setMode, setAccent } = useTheme.getState();

  const mode = values["ui.themeMode"];
  if (typeof mode === "string" && MODES.includes(mode as ThemeMode)) {
    setMode(mode as ThemeMode);
  }

  const accent = values["ui.accent"];
  if (typeof accent === "string" && ACCENTS.includes(accent as Accent)) {
    setAccent(accent as Accent);
  }
}

/** 设置数据到达后同步一次远程外观。 */
export function useThemeSync(
  values: Record<string, string | number | boolean> | undefined,
): void {
  useEffect(() => {
    applyRemoteTheme(values);
  }, [values]);
}
