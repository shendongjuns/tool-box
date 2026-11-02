# 快速开始

从零到跑起来。

## 你需要什么

- **Node.js** 22.12 或更新
- **pnpm** 11 或更新 —— 没装的话执行 `corepack enable`

桌面端额外需要：

- **Rust** stable（[rustup.rs](https://rustup.rs)）
- **MSVC 工具链** —— 安装 Visual Studio 时勾选「使用 C++ 的桌面开发」

## 网页端

```bash
git clone https://github.com/shendongjuns/tool-box.git
cd tool-box

pnpm install
pnpm dev
```

打开 **http://127.0.0.1:5173**。

第一次进入会让你注册。用户名和密码都由你定，**注册完这个入口就关闭了**——单用户系统，不会再有第二个账号。

> 密码没有格式限制，非空即可。忘了只能重来，见[常见问题](./faq.md#忘记密码了)。

## 桌面端

确保已装 Rust 与 MSVC 工具链，然后：

```bash
pnpm desktop:dev      # 开发模式（热重载）
pnpm desktop:build    # 打包成安装程序
```

打包产物在 `apps/desktop/src-tauri/target/release/bundle/`：

- `nsis/ToolBox_x.y.z_x64-setup.exe` —— 安装包
- `portable/ToolBox-x.y.z-portable.zip` —— 免安装，解压即用

## 只跑其中一半

```bash
pnpm dev:server   # 只有 API，端口 7788
pnpm dev:web      # 只有前端，端口 5173（会代理 /api 到 7788）
```

## 换个端口

```bash
PORT=8080 pnpm dev
```

这个变量服务端和前端代理都读，所以不用改两处。

> **为什么默认是 7788？** Windows 的 Hyper-V / WSL 会保留一段动态端口，常用的 3000 经常落在保留区里，导致启动时 `EACCES`。7788 远离这些区间。

## 用 Docker 跑服务端

不想装 Node 的话，直接跑容器：

```bash
git clone https://github.com/shendongjuns/tool-box.git
cd tool-box/docker
docker compose up -d --build
```

访问 **http://127.0.0.1:7788**。数据落在宿主机的 `docker/data/`。

细节见[部署](./deploy.md)。

## 下一步

- [部署到服务器](./deploy.md)
- [升级与备份](./upgrade.md)
- [常见问题](./faq.md)
