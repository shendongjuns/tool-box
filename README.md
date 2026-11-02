<div align="center">

# ToolBox

**自托管的个人工具箱**

编码工具 · SSH 终端 · 文件传输 · 系统监控

</div>

---

一个自己用的工具箱。单用户，数据在自己机器上——本地 SQLite，或者你自己的服务器。

没有账号体系，没有云端依赖，没有遥测。

网页端与 Windows 桌面端共用一套代码。桌面端把整个程序连同数据装进一个文件夹，拷走即迁移。

## 里面有什么

**编码** — JSON 格式化、Base64、URL 编解码、时间戳、哈希、UUID

**远程** — SSH 终端（多会话、主机指纹校验）、SFTP 文件管理、系统监控（CPU / 内存 / 磁盘 / 网络 / GPU / NPU）

## 快速开始

```bash
pnpm install
pnpm dev
```

打开 http://127.0.0.1:5173，首次进入会要求注册。

桌面端：

```bash
pnpm desktop:dev      # 开发
pnpm desktop:build    # 打包
```

## 文档

|                                |                                |
| ------------------------------ | ------------------------------ |
| [快速开始](docs/quickstart.md) | 环境要求、端口配置、开发模式   |
| [部署](docs/deploy.md)         | Docker、反向代理、环境变量     |
| [升级与备份](docs/upgrade.md)  | 数据迁移、自动备份、回滚       |
| [常见问题](docs/faq.md)        | 忘记密码、SSH 指纹、疑难排查   |
| [更新日志](CHANGELOG.md)       | 每个版本改了什么、能不能直接升 |

## 一些边界

**单用户是刻意的。** 没有角色、没有权限组、没有审批流。

**只打包 Windows。** 网页端跨平台，桌面端目前只出 Windows 版。

**本地加密有边界。** 它能挡住「拿到数据库文件」的人；如果攻击者已经能以你的身份运行程序，任何本地加密都挡不住。

## 改点什么

```bash
pnpm lint        # 代码检查
pnpm test        # 测试
pnpm typecheck   # 类型检查
```

工具目录在 `packages/contracts/src/tool-catalog.ts`。

## 许可证

MIT
