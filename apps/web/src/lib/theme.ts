import { create } from "zustand";
import type { Accent, ThemeMode } from "@toolbox/contracts";

interface ThemeState {
  mode: ThemeMode;
  accent: Accent;
  resolved: "light" | "dark";
  setMode: (mode: ThemeMode) => void;
  setAccent: (accent: Accent) => void;
  apply: () => void;
}

const media = () => window.matchMedia("(prefers-color-scheme: dark)");

function resolve(mode: ThemeMode): "light" | "dark" {
  if (mode === "system") return media().matches ? "dark" : "light";
  return mode;
}

function paint(mode: ThemeMode, accent: Accent) {
  const resolved = resolve(mode);
  const root = document.documentElement;
  root.classList.toggle("dark", resolved === "dark");
  if (accent === "indigo") root.removeAttribute("data-accent");
  else root.setAttribute("data-accent", accent);
  root.style.colorScheme = resolved;
  return resolved;
}

/**
 * 默认跟随系统。resolved 初值在浏览器里直接算一次，
 * 避免首帧用 "dark" 造成闪烁，也避免在 SSR 环境下访问 window。
 */
const initialMode: ThemeMode = "system";
const initialResolved: "light" | "dark" =
  typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";

export const useTheme = create<ThemeState>((set, get) => ({
  mode: initialMode,
  accent: "indigo",
  resolved: initialResolved,
  setMode: (mode) => {
    set({ mode, resolved: paint(mode, get().accent) });
  },
  setAccent: (accent) => {
    set({ accent, resolved: paint(get().mode, accent) });
  },
  apply: () => {
    set({ resolved: paint(get().mode, get().accent) });
  },
}));

/** 首次挂载时同步一次系统主题，并监听系统切换。 */
export function initTheme(): () => void {
  useTheme.getState().apply();
  const listener = () => {
    if (useTheme.getState().mode === "system") useTheme.getState().apply();
  };
  const query = media();
  query.addEventListener("change", listener);
  return () => query.removeEventListener("change", listener);
}
