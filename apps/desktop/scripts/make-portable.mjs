#!/usr/bin/env node
/**
 * 生成免安装版（portable zip）。
 *
 * Tauri 的 bundle.targets 在 Windows 上只支持 nsis / msi，
 * 所以「绿色版」由这个脚本在 tauri build 之后完成：
 *
 *   1. 取 target/release 下的 exe
 *   2. 在临时目录里建好 ToolBox/ 结构（exe + README）
 *   3. 压成 ToolBox-<version>-portable.zip
 *
 * 数据目录在运行时创建在 exe 旁边（<exe>/data），
 * 因此解压即用，整个文件夹拷走即可迁移。
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync, copyFileSync, writeFileSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const releaseDir = join(root, "src-tauri", "target", "release");
const exePath = join(releaseDir, "toolbox-desktop.exe");
const outDir = join(root, "src-tauri", "target", "release", "bundle", "portable");
const stageDir = join(outDir, "ToolBox");

if (!existsSync(exePath)) {
  console.error("找不到已构建的 exe，先运行 pnpm build");
  process.exit(1);
}

const conf = JSON.parse(readFileSync(join(root, "src-tauri", "tauri.conf.json"), "utf8"));
const version = conf.version ?? "0.0.0";

rmSync(outDir, { recursive: true, force: true });
mkdirSync(stageDir, { recursive: true });

copyFileSync(exePath, join(stageDir, "ToolBox.exe"));

writeFileSync(
  join(stageDir, "使用说明.txt"),
  [
    "ToolBox " + version + "（免安装版）",
    "",
    "1. 双击 ToolBox.exe 运行，无需安装。",
    "2. 所有数据保存在本目录下的 data\\ 文件夹内（数据库、日志、窗口状态）。",
    "3. 迁移或备份：直接复制整个文件夹。",
    "4. 卸载：关闭程序后删除整个文件夹即可。",
    "",
    "需要 WebView2 运行时（Windows 11 与较新的 Windows 10 已自带）。",
    "若无法启动，请安装：https://developer.microsoft.com/microsoft-edge/webview2/",
  ].join("\r\n"),
);

const zipPath = join(outDir, `ToolBox-${version}-portable.zip`);
if (existsSync(zipPath)) rmSync(zipPath);

execFileSync(
  "powershell",
  [
    "-NoProfile",
    "-Command",
    `Compress-Archive -Path '${stageDir}' -DestinationPath '${zipPath}' -Force`,
  ],
  { stdio: "inherit" },
);

console.log("已生成：" + zipPath);
