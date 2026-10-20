import { create } from "zustand";
import type { DataSource } from "./platform";
import { isDesktop } from "./platform";

const SOURCE_KEY = "toolbox.dataSource";
const CLOUD_URL_KEY = "toolbox.cloudBaseUrl";
const LOCAL_INIT_KEY = "toolbox.localInitialized";

export const DEFAULT_CLOUD_URL = "http://localhost:3000";

export interface DataSourceConfig {
  /** 当前数据源；网页端恒为 cloud */
  source: DataSource;
  /** 云端地址（桌面端可改） */
  cloudBaseUrl: string;
  /** 本地模式是否已创建账号 */
  localInitialized: boolean;
}

interface DataSourceState extends DataSourceConfig {
  setCloudBaseUrl: (url: string) => void;
  setSource: (source: DataSource) => void;
  setLocalInitialized: (value: boolean) => void;
  load: () => void;
}

function readInitialSource(): DataSource {
  if (!isDesktop()) return "cloud";
  return localStorage.getItem(SOURCE_KEY) === "cloud" ? "cloud" : "local";
}

export const useDataSource = create<DataSourceState>((set) => ({
  source: "cloud",
  cloudBaseUrl: DEFAULT_CLOUD_URL,
  localInitialized: false,

  setCloudBaseUrl: (url) => {
    const normalized = url.trim().replace(/\/$/, "");
    localStorage.setItem(CLOUD_URL_KEY, normalized);
    set({ cloudBaseUrl: normalized });
  },

  setSource: (source) => {
    localStorage.setItem(SOURCE_KEY, source);
    set({ source });
  },

  setLocalInitialized: (value) => {
    localStorage.setItem(LOCAL_INIT_KEY, String(value));
    set({ localInitialized: value });
  },

  load: () => {
    if (typeof window === "undefined") return;
    set({
      source: readInitialSource(),
      cloudBaseUrl: localStorage.getItem(CLOUD_URL_KEY) ?? DEFAULT_CLOUD_URL,
      localInitialized: localStorage.getItem(LOCAL_INIT_KEY) === "true",
    });
  },
}));

/** 当前数据源的基地址：本地模式走 Tauri 本地服务，不使用公网地址。 */
export function baseUrlFor(state: Pick<DataSourceState, "source" | "cloudBaseUrl">): string {
  return state.source === "cloud" ? state.cloudBaseUrl : "";
}
