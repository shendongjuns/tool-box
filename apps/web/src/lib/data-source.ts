import { create } from "zustand";
import { isDesktop } from "./platform";

/**
 * 数据源。
 *
 * 页面本身**不区分**本地与云端：所有页面只有一套 UI。
 * 区别只在「数据从哪儿来」——本地 SQLite，或用户自己添加的某个云端地址。
 *
 * - `local`：桌面端内置，固定身份「（本地）」，无需登录。
 * - `cloud`：用户自己创建的服务器地址，需要账号密码。
 */
export type DataSourceType = "local" | "cloud";

export interface CloudSource {
  /** 稳定 id，用于持久化与缓存键 */
  id: string;
  /** 用户起的名字，显示在左下角与切换列表 */
  name: string;
  /** 服务器地址，例如 http://192.168.1.10:3000 */
  url: string;
}

export interface DataSourceState {
  /** 当前选中的数据源 */
  activeId: string;
  /** 用户创建的云端数据源（可多个） */
  cloudSources: CloudSource[];
  /** 当前数据源类型 */
  type: DataSourceType;
  /** 当前云端地址（type=cloud 时有值） */
  cloudBaseUrl: string;
  /** 当前数据源显示名（左下角徽标用） */
  label: string;

  load: () => void;
  /** 选中某个数据源；返回 true 表示需要重新登录 */
  select: (id: string) => boolean;
  addCloud: (input: { name: string; url: string }) => CloudSource;
  removeCloud: (id: string) => void;
  renameCloud: (id: string, name: string) => void;
}

const SOURCES_KEY = "toolbox.sources";
const ACTIVE_KEY = "toolbox.activeSource";
const LEGACY_URL_KEY = "toolbox.cloudBaseUrl";

export const LOCAL_SOURCE: CloudSource = {
  id: "local",
  name: "本地数据",
  url: "",
};

/** 默认云端地址：本机服务端，方便本地开发/自托管起步。 */
const DEFAULT_CLOUD: CloudSource = {
  id: "cloud-default",
  name: "默认服务器",
  url: "http://127.0.0.1:3000",
};

function normalizeUrl(url: string): string {
  return url.trim().replace(/\/$/, "");
}

function readSources(): CloudSource[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(SOURCES_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter(
        (item): item is CloudSource =>
          typeof item === "object" &&
          item !== null &&
          typeof (item as CloudSource).id === "string" &&
          typeof (item as CloudSource).name === "string" &&
          typeof (item as CloudSource).url === "string",
      )
      .map((item) => ({ ...item, url: normalizeUrl(item.url) }));
  } catch {
    return [];
  }
}

function persistSources(sources: CloudSource[]): void {
  localStorage.setItem(SOURCES_KEY, JSON.stringify(sources));
}

function resolveState(activeId: string, sources: CloudSource[]) {
  if (activeId === "local") {
    return { activeId, type: "local" as const, cloudBaseUrl: "", label: LOCAL_SOURCE.name };
  }
  const found = sources.find((item) => item.id === activeId);
  if (found) {
    return {
      activeId,
      type: "cloud" as const,
      cloudBaseUrl: found.url,
      label: found.name,
    };
  }
  // 没找到就退回家具默认值
  return {
    activeId: "local",
    type: "local" as const,
    cloudBaseUrl: "",
    label: LOCAL_SOURCE.name,
  };
}

export const useDataSource = create<DataSourceState>((set, get) => ({
  activeId: "local",
  cloudSources: [],
  type: "local",
  cloudBaseUrl: "",
  label: LOCAL_SOURCE.name,

  load: () => {
    if (typeof window === "undefined") return;

    let sources = readSources();
    // 迁移旧版的单个 cloudBaseUrl
    const legacy = localStorage.getItem(LEGACY_URL_KEY);
    if (legacy && sources.length === 0) {
      const migrated: CloudSource = {
        id: "cloud-migrated",
        name: "我的服务器",
        url: normalizeUrl(legacy),
      };
      sources = [migrated];
      persistSources(sources);
      localStorage.removeItem(LEGACY_URL_KEY);
    }

    // 网页端没有本地数据源：默认选第一个云端，没有就建默认
    if (!isDesktop()) {
      if (sources.length === 0) {
        sources = [DEFAULT_CLOUD];
        persistSources(sources);
      }
      const stored = localStorage.getItem(ACTIVE_KEY);
      const active = sources.some((item) => item.id === stored) ? stored! : sources[0]!.id;
      set({ cloudSources: sources, ...resolveState(active, sources) });
      return;
    }

    const stored = localStorage.getItem(ACTIVE_KEY);
    const active =
      stored === "local" || sources.some((item) => item.id === stored)
        ? stored!
        : "local"; // 桌面端默认本地
    set({ cloudSources: sources, ...resolveState(active, sources) });
  },

  select: (id) => {
    const state = get();
    const next = resolveState(id, state.cloudSources);
    localStorage.setItem(ACTIVE_KEY, next.activeId);
    set(next);
    return next.activeId !== state.activeId;
  },

  addCloud: ({ name, url }) => {
    const source: CloudSource = {
      id: `cloud-${Date.now().toString(36)}`,
      name: name.trim(),
      url: normalizeUrl(url),
    };
    const sources = [...get().cloudSources, source];
    persistSources(sources);
    set({ cloudSources: sources });
    return source;
  },

  removeCloud: (id) => {
    const sources = get().cloudSources.filter((item) => item.id !== id);
    persistSources(sources);
    const state: Partial<DataSourceState> = { cloudSources: sources };
    if (get().activeId === id) {
      localStorage.setItem(ACTIVE_KEY, "local");
      Object.assign(state, resolveState("local", sources));
    }
    set(state as DataSourceState);
  },

  renameCloud: (id, name) => {
    const sources = get().cloudSources.map((item) =>
      item.id === id ? { ...item, name: name.trim() } : item,
    );
    persistSources(sources);
    const state: Partial<DataSourceState> = { cloudSources: sources };
    if (get().activeId === id) {
      Object.assign(state, resolveState(id, sources));
    }
    set(state as DataSourceState);
  },
}));

/** 缓存键：数据源变化时用它区分 Query 缓存，避免两套数据串台。 */
export function currentSourceKey(
  state: Pick<DataSourceState, "activeId" | "cloudBaseUrl">,
): string {
  return state.activeId === "local" ? "local" : `cloud:${state.cloudBaseUrl}`;
}
