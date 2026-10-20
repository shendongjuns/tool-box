# ToolBox 2.0

**网页端 + 桌面端的现代工具箱。** React 19 + Tauri 2 + SQLite，单用户私有部署，
桌面端可在「本地数据」与「云端数据」两套完全独立的数据源之间切换。

> 2.0 是一次彻底重写：1.x 的 Flutter/ForUI 实现已整体移除（历史保留在 `v1.5.0` tag），
> **不提供 1.x 数据迁移**。

---

## 特性

- **漂亮且可定制** —— shadcn/ui + Tailwind v4，OKLCH 语义色，深浅色 + 六套强调色，全部落库到当前数据源。
- **双数据源，互不覆盖** —— 桌面端默认使用本地 SQLite（断网可用），可在设置中切换到云端；两套库各有一套账号，永不互相同步。
- **单用户 + 30 天会话** —— 首次访问引导注册；Argon2id 存密码；会话 30 天、使用中滑动续期、改密自动下线其他设备。
- **一条命令部署** —— Docker Compose + Caddy 自动 HTTPS，SQLite 挂卷持久化。
- **轻量桌面端** —— Tauri 2 + 系统 WebView2，安装包约 6–10MB（对比 Electron 的 100MB+）。
- **完整工具框架** —— 内置 JSON 格式化、Base64、URL 编解码、时间戳、哈希、UUID，可按约定扩展。

## 技术栈

| 层 | 选型 |
| --- | --- |
| 前端 | React 19 · Vite 7 · TypeScript 5.9 · TanStack Router / Query · Zustand |
| UI | shadcn/ui 风格组件 + Radix 原语 · Tailwind CSS v4 · lucide-react · sonner |
| 服务端 | Fastify 5 · Drizzle ORM · better-sqlite3 · @node-rs/argon2 · Zod |
| 桌面端 | Tauri 2 · Rust · rusqlite（本地数据）· WebView2 |
| 部署 | Docker Compose · Caddy |

## 目录结构

```
tool-box/
├─ apps/
│  ├─ server/        Fastify 服务：认证、设置、工具、静态托管
│  ├─ web/           React SPA（网页端与桌面渲染层共用）
│  └─ desktop/       Tauri 2 外壳（Rust 侧含本地数据服务）
├─ packages/
│  ├─ contracts/     Zod schema / DTO / 内置工具目录（前后端唯一真源）
│  ├─ data/          Drizzle schema + 迁移 + repository
│  └─ api-client/    传输层与接口封装
├─ docker/           Dockerfile · compose.yml · Caddyfile
└─ docs/plan-2.0/    实施计划（index.html）与可点击原型（prototype.html）
```

## 快速开始

需要 **Node 24+**、**pnpm 11+**（桌面端另需 Rust stable + MSVC 工具链）。

```bash
pnpm install

# 同时启动服务端（:3000）与网页端（:5173，已配置 /api 代理）
pnpm dev
```

打开 http://localhost:5173 → 首次访问是**注册页**，创建账号后直接进入。

```bash
pnpm build        # 构建 contracts / data / web / server
pnpm test         # 服务端集成测试（Vitest）
pnpm typecheck    # 全仓类型检查（含 cargo check）
pnpm lint         # ESLint
```

## 本地 / 云端双数据源

|  | 本地数据（桌面端默认） | 云端数据 |
| --- | --- | --- |
| 位置 | `%APPDATA%\com.shendongjuns.toolbox\local.db` | 服务器 `/app/data/toolbox.db` |
| 网络 | 不需要，可离线 | 需要 |
| 账号 | 本机独立账号 | 与网页端共用 |
| 关系 | **两套数据完全独立**：不同步、不覆盖、不合并 | |

切换入口：**设置 → 通用 → 数据源**（或桌面端登录页顶部）。切换后需要重新登录对应数据源，
原数据源的数据原样保留，切回来即可继续使用。

实现上，桌面端启动时会在 `127.0.0.1` 的随机端口起一个极小的本地 HTTP 服务（Rust + rusqlite），
接口形状与云端一致，因此页面代码无需区分数据来源。

## 部署（云端）

```bash
cp docker/.env.example docker/.env
# 编辑 docker/.env：DOMAIN、PUBLIC_ORIGIN、SETUP_TOKEN（建议设置）
cd docker && docker compose up -d --build
```

打开 `https://你的域名` 完成首次注册。

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `PORT` | 3000 | 监听端口 |
| `DATABASE_PATH` | ./data/toolbox.db | SQLite 文件路径 |
| `PUBLIC_ORIGIN` | http://localhost:5173 | 允许来源（CSRF 校验），多个用逗号分隔 |
| `SESSION_TTL_DAYS` | 30 | 会话有效期 |
| `COOKIE_SECURE` | false | 生产环境务必 true |
| `TRUST_PROXY` | false | 在反代后设为 true |
| `SETUP_TOKEN` | 空 | 一次性注册口令，留空则不校验 |
| `BACKUP_KEEP` | 7 | 备份保留份数 |

> **安全提示**：首次注册前不要把服务暴露到公网，或务必设置 `SETUP_TOKEN`。
> 备份直接拷贝 `docker/data` 目录即可。

## 桌面端

```bash
pnpm --filter @toolbox/web dev        # 终端 A：前端
pnpm --filter @toolbox/desktop dev    # 终端 B：Tauri 外壳
```

打包：

```bash
pnpm --filter @toolbox/web build
pnpm --filter @toolbox/desktop build   # 产物在 apps/desktop/src-tauri/target/release/bundle/
```

- 托盘常驻：单击显示窗口，右键「显示主窗口 / 退出 ToolBox」；关闭按钮默认最小化到托盘。
- 单实例：重复启动只会聚焦已有窗口。
- 自动更新：`plugin-updater` + GitHub Releases，签名私钥通过 `TAURI_SIGNING_PRIVATE_KEY` 注入 CI。
- 未签名安装包会触发 Windows SmartScreen 提示，属正常现象。

## 安全设计

- 密码：Argon2id（19456 KiB / t=2 / p=1）；本地库使用加盐 SHA-256。
- 会话：令牌 `base64url(randomBytes(32))`，库中只存 `sha256`；Cookie `HttpOnly`、`SameSite=Lax`、生产 `Secure`。
- CSRF：非安全方法校验 `Origin`；桌面端使用 Bearer 令牌，天然免疫。
- 限流：登录 10 次/分钟/IP，首次注册 5 次/分钟/IP。
- 本地服务仅绑定 `127.0.0.1`，随机端口，且同样校验令牌。

## 已知限制

- 单用户，无多租户与角色体系。
- 中文界面，暂未做多语言。
- 桌面端目前面向 Windows（Tauri 理论上可打包 macOS/Linux，未验证）。
- 未做 1.x 数据迁移。

## 许可证

[MIT](LICENSE) © shendongjuns
