import { create } from "zustand";
import type { DataSource } from "./platform";
import { isDesktop } from "./platform";

const SOURCE_KEY = "toolbox.dataSource";
const CLOUD_URL_KEY = "toolbox.cloudBaseUrl";

/**
 * 桌面端默认连本机服务器；用户可在设置里改成自己的云端地址。
 * 用 127.0.0.1 而不是 localhost：Windows 上 localhost 可能优先解析到 ::1，
 * 而服务端默认只监听 IPv4。
 */
export const DEFAULT_CLOUD_URL = "http://127.0.0.1:3000";

export interface DataSourceConfig {
  /** 当前数据源；网页端恒为 cloud */
  source: DataSource;
  /** 云端地址（桌面端可改） */
  cloudBaseUrl: string;
}

interface DataSourceState extends DataSourceConfig {
  setCloudBaseUrl: (url: string) => void;
  setSource: (source: DataSource) => void;
  load: () => void;
}

function readInitialSource(): DataSource {
  if (!isDesktop()) return "cloud";
  return localStorage.getItem(SOURCE_KEY) === "cloud" ? "cloud" : "local";
}

export const useDataSource = create<DataSourceState>((set) => ({
  source: "cloud",
  cloudBaseUrl: DEFAULT_CLOUD_URL,

  setCloudBaseUrl: (url) => {
    const normalized = url.trim().replace(/\/$/, "");
    localStorage.setItem(CLOUD_URL_KEY, normalized);
    set({ cloudBaseUrl: normalized });
  },

  setSource: (source) => {
    localStorage.setItem(SOURCE_KEY, source);
    set({ source });
  },

  load: () => {
    if (typeof window === "undefined") return;
    set({
      source: readInitialSource(),
      cloudBaseUrl: localStorage.getItem(CLOUD_URL_KEY) ?? DEFAULT_CLOUD_URL,
    });
  },
}));

/** 缓存键：数据源变化时用它区分 Query 缓存，避免两套数据串台。 */
export function sourceKey(source: DataSource, cloudBaseUrl: string): string {
  return source === "cloud" ? `cloud:${cloudBaseUrl}` : "local";
}
