# 桌面端（Tauri 2）

同一个 React 前端，两种形态：

- **网页端**：浏览器访问服务器。
- **桌面端**：Tauri 外壳（Rust + 系统 WebView2），安装包体积约 6–10MB。

## 目录约定

```
apps/desktop/
├─ src-tauri/            Rust 侧：窗口、托盘、单实例、本地数据库
│  ├─ src/main.rs
│  ├─ src/local_api.rs   本地数据源 HTTP 服务（127.0.0.1 随机端口）
│  ├─ src/lib.rs
│  ├─ tauri.conf.json
│  ├─ Cargo.toml
│  └─ migrations/        与 packages/data 共用同一份 SQL
└─ README.md
```

## 本地 / 云端双数据源

| 模式 | 数据位置 | 网络 | 说明 |
| --- | --- | --- | --- |
| 本地（默认） | `%APPDATA%\com.shendongjuns.toolbox\local.db` | 不需要 | 本机独立账号与数据 |
| 云端 | 服务器 `toolbox.db` | 需要 | 与网页端共享同一账号体系 |

两套数据**完全独立**：切换数据源只改变「读哪一套」，绝不复制、绝不覆盖。
切换入口：设置 → 通用 → 数据源（或登录页顶部的切换按钮）。

## 开发

```bash
# 1. 先启动服务端（云端模式需要）
pnpm --filter @toolbox/server dev

# 2. 启动桌面端（会同时起 Vite）
pnpm --filter @toolbox/web dev      # 终端 A
pnpm --filter @toolbox/desktop dev  # 终端 B
```

## 打包

```bash
pnpm --filter @toolbox/web build             # 先产出前端
pnpm --filter @toolbox/desktop build         # 产出 NSIS 安装包
```

产物在 `apps/desktop/src-tauri/target/release/bundle/`。

## 签名与更新

- 更新签名私钥由 `TAURI_SIGNING_PRIVATE_KEY` 注入，**不要提交到仓库**。
- 丢失私钥 = 无法再向已安装用户推送更新，务必离线备份。
