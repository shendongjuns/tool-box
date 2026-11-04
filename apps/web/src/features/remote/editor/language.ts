import { StreamLanguage } from "@codemirror/language";
import { json } from "@codemirror/lang-json";
import { javascript } from "@codemirror/lang-javascript";
import { css } from "@codemirror/lang-css";
import { html } from "@codemirror/lang-html";
import { markdown } from "@codemirror/lang-markdown";
import { sql } from "@codemirror/lang-sql";
import { python } from "@codemirror/lang-python";
import { shell } from "@codemirror/legacy-modes/mode/shell";
import { properties } from "@codemirror/legacy-modes/mode/properties";
import { yaml } from "@codemirror/legacy-modes/mode/yaml";
import { nginx } from "@codemirror/legacy-modes/mode/nginx";
import { dockerFile } from "@codemirror/legacy-modes/mode/dockerfile";
import { toml } from "@codemirror/legacy-modes/mode/toml";
import type { Extension } from "@codemirror/state";

/**
 * 按文件名推断语法高亮。
 *
 * 两类信息都要用：
 * - 扩展名（.json / .sh / .py）
 * - 完整文件名（Dockerfile / Makefile / nginx.conf 没有有意义的扩展名）
 *
 * 认不出来就返回 null，编辑器退化成纯文本 —— 不影响使用。
 */

/** 只看扩展名的映射。 */
const BY_EXT: Record<string, () => Extension> = {
  json: () => json(),
  jsonc: () => json(),
  js: () => javascript(),
  mjs: () => javascript(),
  cjs: () => javascript(),
  ts: () => javascript({ typescript: true }),
  tsx: () => javascript({ typescript: true, jsx: true }),
  jsx: () => javascript({ jsx: true }),
  css: () => css(),
  scss: () => css(),
  less: () => css(),
  html: () => html(),
  htm: () => html(),
  vue: () => html(),
  md: () => markdown(),
  markdown: () => markdown(),
  sql: () => sql(),
  py: () => python(),
  sh: () => StreamLanguage.define(shell),
  bash: () => StreamLanguage.define(shell),
  zsh: () => StreamLanguage.define(shell),
  ini: () => StreamLanguage.define(properties),
  conf: () => StreamLanguage.define(properties),
  cfg: () => StreamLanguage.define(properties),
  properties: () => StreamLanguage.define(properties),
  env: () => StreamLanguage.define(properties),
  yaml: () => StreamLanguage.define(yaml),
  yml: () => StreamLanguage.define(yaml),
  toml: () => StreamLanguage.define(toml),
};

/** 只看完整文件名的映射（这类文件通常没有扩展名）。 */
const BY_NAME: Record<string, () => Extension> = {
  dockerfile: () => StreamLanguage.define(dockerFile),
  "docker-compose.yml": () => StreamLanguage.define(yaml),
  "docker-compose.yaml": () => StreamLanguage.define(yaml),
  makefile: () => StreamLanguage.define(shell),
  ".gitignore": () => StreamLanguage.define(properties),
  ".env": () => StreamLanguage.define(properties),
  ".env.example": () => StreamLanguage.define(properties),
  nginx: () => StreamLanguage.define(nginx),
};

/** 文件名里含这些片段时按 nginx 配置处理。 */
const NGINX_HINTS = ["nginx.conf", "sites-available", "sites-enabled", "conf.d"];

export function detectLanguage(path: string): Extension | null {
  const name = path.split("/").pop()?.toLowerCase() ?? "";
  if (!name) return null;

  const byName = BY_NAME[name];
  if (byName) return byName();

  if (NGINX_HINTS.some((hint) => path.toLowerCase().includes(hint))) {
    return StreamLanguage.define(nginx);
  }

  const ext = name.includes(".") ? name.split(".").pop() : undefined;
  if (!ext) return null;

  const byExt = BY_EXT[ext];
  return byExt ? byExt() : null;
}
