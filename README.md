<div align="center">

# ToolBox

**一个自托管的现代工具箱 · 网页端 + 桌面端 · 数据完全归你所有**

React 19 · Tauri 2 · Fastify 5 · SQLite

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![React](https://img.shields.io/badge/React-19-61dafb?logo=react&logoColor=white)](https://react.dev)
[![Tauri](https://img.shields.io/badge/Tauri-2-24c8db?logo=tauri&logoColor=white)](https://tauri.app)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.9-3178c6?logo=typescript&logoColor=white)](https://www.typescriptlang.org)

[特性](#特性) · [截图](#截图) · [快速开始](#快速开始) · [部署](#部署) · [桌面端](#桌面端) · [开发](#开发)

</div>

---

## 这是什么

ToolBox 是一个**单用户**、**可自托管**的工具箱。同一套 React 代码有两种形态：

- **网页端** —— 浏览器打开就能用，数据存在自己的服务器上。
- **桌面端** —— Windows 安装包（约 3MB），基于 Tauri 2；默认把数据存在本机，**断网也能用**。

桌面端支持「本地 / 云端」多数据源，两套数据彼此完全独立，随时切换、互不覆盖。

## 截图

<div align="center">
  <img src="assets/login.png" alt="登录页" width="100%" />
  <br />
  <sub>登录页 · 浅色</sub>
</div>

<details>
<summary>深色模式</summary>

<div align="center">
  <img src="assets/login-dark.png" alt="登录页深色" width="100%" />
</div>

</details>

## 特性

| | |
| --- | --- |
| **界面** | Tailwind v4 + OKLCH 语义色，深浅色主题与六套强调色 |
| **多数据源** | 桌面端默认本地，可添加多个云端地址；切换后回到登录页 |
| **单用户** | 首次打开引导创建账号，之后不再提供注册入口 |
| **30 天会话** | 使用中自动滑动续期，改密自动下线其它设备 |
| **一条命令部署** | Docker Compose 启动，SQLite 挂卷持久化 |
| **轻量桌面端** | Tauri 2 + 系统 WebView2，安装包约 3MB |
| **可扩展** | 内置 6 个工具，新增只需改两处 |

### 内置工具

三级目录组织：**编码** → 格式化 / 编解码 / 生成器 / 加密哈希 → 具体工具。

| 工具 | 说明 |
| --- | --- |
| JSON 格式化 | 格式化、压缩、合法性校验 |
| Base64 编解码 | 支持 URL 安全字符集 |
| URL 编解码 | 组件级编码 / 解码 |
| 时间戳转换 | Unix 时间戳 ⇄ 本地时间 |
| 哈希计算 | MD5 / SHA-1 / SHA-256 |
| UUID 生成器 | 批量生成 v4 |

## 技术栈

| 层 | 技术 |
| --- | --- |
| 前端 | React 19 · Vite 7 · TypeScript 5.9 · TanStack Router / Query · Zustand |
| UI | Radix 原语 · Tailwind CSS v4 · lucide-react |
| 服务端 | Fastify 5 · Drizzle ORM · better-sqlite3 · Argon2id · Zod |
| 桌面端 | Tauri 2 · Rust · rusqlite · WebView2 |
| 部署 | Docker · SQLite 单文件数据库 |

## 快速开始

**环境要求**：Node.js 24+、pnpm 11+（桌面端另需 Rust stable 与 MSVC 工具链）

```bash
git clone https://github.com/shendongjuns/tool-box.git
cd tool-box
pnpm install
pnpm dev
```

打开 <http://localhost:5173>。首次访问显示「创建账号」，填用户名与密码即可开始 —— 这是系统里唯一的账号。

> 服务端默认监听 `0.0.0.0:7788`，前端开发服务器把 `/api` 代理过去。

## 部署

应用只负责在本机监听 HTTP，**不关心域名、HTTPS 与证书** —— 交给反向代理或隧道。

```bash
cd docker
docker compose up -d --build
```

默认映射到 `127.0.0.1:7788`，只允许本机访问。需要局域网直接访问时，把 `compose.yml` 里的端口映射改成 `"7788:7788"`。

数据库是单个 SQLite 文件（`docker/data/toolbox.db`），备份直接拷贝该目录即可。

### 配置

全部通过环境变量传入，均有合理默认值：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `PORT` | `7788` | 监听端口 |
| `HOST` | `0.0.0.0` | 监听地址 |
| `DATABASE_PATH` | `./data/toolbox.db` | SQLite 文件路径 |
| `SESSION_TTL_DAYS` | `30` | 会话有效期（天） |
| `SESSION_RENEW_THROTTLE_MIN` | `5` | 滑动续期写库节流（分钟） |
| `TRUST_PROXY` | `true` | 是否信任 `X-Forwarded-*` 头 |
| `LOG_LEVEL` | `info` | 日志级别 |

## 桌面端

```bash
pnpm --filter @toolbox/desktop dev      # 开发
pnpm --filter @toolbox/desktop build    # 打包（含 NSIS 安装包）
node apps/desktop/scripts/make-portable.mjs   # 免安装 zip
```

产物：

| 文件 | 说明 |
| --- | --- |
| `bundle/nsis/ToolBox_x64-setup.exe` | 安装包：可选目录、创建快捷方式 |
| `bundle/portable/ToolBox-portable.zip` | 免安装：解压即用，删除即卸载 |

桌面端启动时在 `127.0.0.1` 的随机端口起一个本地 SQLite 服务（Rust + rusqlite），前端通过 `invoke("local_api_port")` 拿到端口后请求，因此页面代码与云端模式完全一致。

- 托盘常驻：单击显示窗口，右键「显示主窗口 / 退出」
- **关闭窗口 = 隐藏到托盘**（不弹确认框），彻底退出用托盘菜单
- 单实例：重复启动只聚焦已有窗口

### 数据位置

所有数据都在 exe 同级的 `data/` 目录，不写 AppData：

```
ToolBox/
├─ ToolBox.exe
└─ data/
   ├─ local.db          本地 SQLite
   ├─ window-state.json 窗口尺寸
   └─ logs/app.log      运行日志
```

备份 = 复制整个文件夹；迁移 = 拷到新机器；卸载 = 删除文件夹。

## 开发

```bash
pnpm dev            # 服务端 + 网页端
pnpm build          # 全量构建
pnpm test           # 服务端集成测试
pnpm typecheck      # 全仓类型检查
pnpm lint           # ESLint
pnpm format         # Prettier
```

### 项目结构

```
tool-box/
├─ apps/
│  ├─ server/        Fastify 服务：认证、设置、工具、静态托管
│  ├─ web/           React SPA（网页端与桌面渲染层共用）
│  └─ desktop/       Tauri 2 外壳（Rust 侧含本地数据服务）
├─ packages/
│  ├─ contracts/     Zod schema / DTO / 工具目录（前后端唯一真源）
│  ├─ data/          Drizzle schema + 迁移 + repository
│  └─ api-client/    传输层与接口封装
└─ docker/           Dockerfile · compose.yml
```

### 新增一个工具

1. 在 `packages/contracts/src/tool-catalog.ts` 登记元信息（id、名称、分组、分类、图标）
2. 在 `apps/web/src/features/tools/` 写组件，并在 `components/tools/tool-runner.tsx` 注册

侧栏、路由、命令面板会自动出现该工具。

## 安全

- 密码使用 **Argon2id**（19456 KiB / t=2 / p=1）存储；不限制长度与字符，只要求非空
- 会话令牌为 32 字节随机数，数据库只存 `sha256` 摘要
- Cookie：`HttpOnly` + `SameSite=Lax`，HTTPS 下自动加 `Secure`
- CSRF：非安全方法校验 `Origin` 与请求 Host 同源
- 限流：登录 10 次/分钟/IP
- 本地服务仅绑定 `127.0.0.1`，随机端口，同样校验令牌
- 桌面端 CSP 禁止渲染层直连外网，云端请求统一经 Rust 转发

## 常见问题

<details>
<summary><b>忘记密码怎么办？</b></summary>

单用户系统没有找回入口。停止服务后删除数据库文件中的 `users` / `sessions` 表数据，重新打开即可重新创建账号。**注意这会清空账号，业务数据仍在。**

- 桌面端：`data/local.db`
- 服务端：`docker/data/toolbox.db`（或 `DATABASE_PATH` 指定的位置）
</details>

<details>
<summary><b>能创建第二个用户吗？</b></summary>

不能，这是刻意的设计。系统只有一个账号，注册入口在首次创建后永久关闭。
</details>

<details>
<summary><b>桌面端的本地数据和云端数据会同步吗？</b></summary>

不会。两套数据完全独立，切换只是换一个数据源连接，不存在同步、覆盖或合并。
</details>

<details>
<summary><b>构建桌面端报 <code>拒绝访问 (os error 5)</code>？</b></summary>

目标 exe 正在运行，先退出 ToolBox 再打包。
</details>

<details>
<summary><b>Windows 11 找不到托盘图标？</b></summary>

系统默认折叠新图标。点任务栏右下角 `^` 展开，或到「设置 → 个性化 → 任务栏 → 其他系统托盘图标」中打开。
</details>

## 贡献

欢迎 Issue 与 PR。提交前请确保 `pnpm lint && pnpm test && pnpm typecheck` 全部通过。

## 许可证

[MIT](LICENSE)