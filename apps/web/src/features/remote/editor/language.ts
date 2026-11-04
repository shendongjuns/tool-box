import { StreamLanguage } from "@codemirror/language";
import type { Extension } from "@codemirror/state";

/**
 * 按文件名推断语法高亮。
 *
 * 语言包**按需动态加载** —— CodeMirror 的语言实现（尤其是
 * javascript / html / sql）加起来有几百 KB，全部静态引入会
 * 让 code-editor 这个 chunk 膨胀到 600KB 以上。
 *
 * 实际上一次只看一个文件，加载一个语言就够。
 * 代价是打开编辑器时多一次网络往返（本地几乎无感）。
 */

/** 语言加载器：返回 CodeMirror 扩展。 */
type Loader = () => Promise<Extension | null>;

/** 只看扩展名的映射。 */
const BY_EXT: Record<string, Loader> = {
  json: async () => (await import("@codemirror/lang-json")).json(),
  jsonc: async () => (await import("@codemirror/lang-json")).json(),

  js: async () => (await import("@codemirror/lang-javascript")).javascript(),
  mjs: async () => (await import("@codemirror/lang-javascript")).javascript(),
  cjs: async () => (await import("@codemirror/lang-javascript")).javascript(),
  jsx: async () => (await import("@codemirror/lang-javascript")).javascript({ jsx: true }),
  ts: async () => (await import("@codemirror/lang-javascript")).javascript({ typescript: true }),
  tsx: async () =>
    (await import("@codemirror/lang-javascript")).javascript({ typescript: true, jsx: true }),

  css: async () => (await import("@codemirror/lang-css")).css(),
  scss: async () => (await import("@codemirror/lang-css")).css(),
  less: async () => (await import("@codemirror/lang-css")).css(),

  html: async () => (await import("@codemirror/lang-html")).html(),
  htm: async () => (await import("@codemirror/lang-html")).html(),
  vue: async () => (await import("@codemirror/lang-html")).html(),

  md: async () => (await import("@codemirror/lang-markdown")).markdown(),
  markdown: async () => (await import("@codemirror/lang-markdown")).markdown(),

  sql: async () => (await import("@codemirror/lang-sql")).sql(),
  py: async () => (await import("@codemirror/lang-python")).python(),

  // legacy-modes 是同一包内的不同模式，一次加载即可复用
  sh: async () => {
    const { shell } = await import("@codemirror/legacy-modes/mode/shell");
    return StreamLanguage.define(shell);
  },
  bash: async () => {
    const { shell } = await import("@codemirror/legacy-modes/mode/shell");
    return StreamLanguage.define(shell);
  },
  zsh: async () => {
    const { shell } = await import("@codemirror/legacy-modes/mode/shell");
    return StreamLanguage.define(shell);
  },
  ini: async () => {
    const { properties } = await import("@codemirror/legacy-modes/mode/properties");
    return StreamLanguage.define(properties);
  },
  conf: async () => {
    const { properties } = await import("@codemirror/legacy-modes/mode/properties");
    return StreamLanguage.define(properties);
  },
  cfg: async () => {
    const { properties } = await import("@codemirror/legacy-modes/mode/properties");
    return StreamLanguage.define(properties);
  },
  properties: async () => {
    const { properties } = await import("@codemirror/legacy-modes/mode/properties");
    return StreamLanguage.define(properties);
  },
  env: async () => {
    const { properties } = await import("@codemirror/legacy-modes/mode/properties");
    return StreamLanguage.define(properties);
  },
  yaml: async () => {
    const { yaml } = await import("@codemirror/legacy-modes/mode/yaml");
    return StreamLanguage.define(yaml);
  },
  yml: async () => {
    const { yaml } = await import("@codemirror/legacy-modes/mode/yaml");
    return StreamLanguage.define(yaml);
  },
  toml: async () => {
    const { toml } = await import("@codemirror/legacy-modes/mode/toml");
    return StreamLanguage.define(toml);
  },
};

/** 只看完整文件名的映射（这类文件通常没有扩展名）。 */
const BY_NAME: Record<string, Loader> = {
  dockerfile: async () => {
    const { dockerFile } = await import("@codemirror/legacy-modes/mode/dockerfile");
    return StreamLanguage.define(dockerFile);
  },
  "docker-compose.yml": BY_EXT["yml"]!,
  "docker-compose.yaml": BY_EXT["yaml"]!,
  makefile: BY_EXT["sh"]!,
  ".gitignore": BY_EXT["properties"]!,
  ".env": BY_EXT["properties"]!,
  ".env.example": BY_EXT["properties"]!,
};

/** 文件名里含这些片段时按 nginx 配置处理。 */
const NGINX_HINTS = ["nginx.conf", "sites-available", "sites-enabled", "conf.d"];

const nginxLoader: Loader = async () => {
  const { nginx } = await import("@codemirror/legacy-modes/mode/nginx");
  return StreamLanguage.define(nginx);
};

/**
 * 找出该文件对应的语言加载器。
 *
 * 返回 null 表示认不出来 —— 编辑器退化成纯文本，不影响使用。
 */
export function findLanguageLoader(path: string): Loader | null {
  const name = path.split("/").pop()?.toLowerCase() ?? "";
  if (!name) return null;

  const byName = BY_NAME[name];
  if (byName) return byName;

  if (NGINX_HINTS.some((hint) => path.toLowerCase().includes(hint))) {
    return nginxLoader;
  }

  const ext = name.includes(".") ? name.split(".").pop() : undefined;
  if (!ext) return null;

  return BY_EXT[ext] ?? null;
}
