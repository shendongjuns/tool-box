import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import type { Accent, ThemeMode } from "@toolbox/contracts";
import { useApi } from "./api-context";
import { useAuth } from "./auth-session";
import { useTheme } from "./theme";

const MODES: ThemeMode[] = ["light", "dark", "system"];
const ACCENTS: Accent[] = ["indigo", "violet", "emerald", "amber", "rose", "slate"];

/**
 * 把服务端保存的外观设置同步到本地主题。
 *
 * 主题模式/强调色存在当前数据源（本地库或云端库）里，
 * 换设备、换数据源都会各自记住自己的外观。
 */
export function useThemeSync(): void {
  const api = useApi();
  const authed = useAuth((state) => state.auth !== null);
  const setMode = useTheme((state) => state.setMode);
  const setAccent = useTheme((state) => state.setAccent);

  const settings = useQuery({
    queryKey: ["settings"],
    queryFn: () => api.getSettings(),
    enabled: authed,
    staleTime: 60_000,
  });

  useEffect(() => {
    const values = settings.data?.values;
    if (!values) return;

    const mode = values["ui.themeMode"];
    if (typeof mode === "string" && MODES.includes(mode as ThemeMode)) {
      setMode(mode as ThemeMode);
    }

    const accent = values["ui.accent"];
    if (typeof accent === "string" && ACCENTS.includes(accent as Accent)) {
      setAccent(accent as Accent);
    }
  }, [settings.data, setMode, setAccent]);
}
