# 部署

三种方式，按省心程度排序。

---

## 方式一：拉取预构建镜像（推荐）

不需要克隆仓库，不用装 Node，也不用编译。

```bash
mkdir -p toolbox && cd toolbox

# 拉取 docker-compose.yml
curl -O https://raw.githubusercontent.com/shendongjuns/tool-box/main/docker/compose.yml
mkdir -p data

# 启动（默认拉 latest）
docker compose up -d
```

访问 **http://127.0.0.1:7788**。

### 指定版本

```bash
# 锁定某个版本，避免 latest 意外升级
TOOLBOX_IMAGE=ghcr.io/shendongjuns/tool-box:v2.1.0 docker compose up -d
```

可用版本见 [Releases](https://github.com/shendongjuns/tool-box/releases)。tag 格式为 `v2.1.0`（带 v）。

### 如果拉取失败

镜像默认是**私有**的。需要先登录：

```bash
# 用 GitHub 用户名 + Personal Access Token（只需 read:packages 权限）
echo $GITHUB_TOKEN | docker login ghcr.io -u 你的用户名 --password-stdin
```

> 仓库公开后，镜像可以在 Package 设置里改为 public，之后就能匿名拉取。

---

## 方式二：从源码构建

想自己编译，或者要改代码时用这个。

```bash
git clone https://github.com/shendongjuns/tool-box.git
cd tool-box/docker

docker compose up -d --build
```

构建约需 3-5 分钟（首次拉基础镜像会更久）。

---

## 方式三：直接运行 Node 进程

不用容器，最透明的方式。需要 Node.js 22.12+ 与 pnpm 11+。

```bash
git clone https://github.com/shendongjuns/tool-box.git
cd tool-box

pnpm install
pnpm build
cd apps/server
node dist/index.js
```

或者用 pnpm 脚本：

```bash
pnpm --filter @toolbox/server start
```

---

## 配置

复制 `.env.example` 为 `.env` 放在 `docker/` 下（方式一、二）或 `apps/server/` 下（方式三）。

| 变量                         | 默认                | 说明                                                               |
| ---------------------------- | ------------------- | ------------------------------------------------------------------ |
| `PORT`                       | `7788`              | 监听端口                                                           |
| `HOST`                       | `0.0.0.0`           | 监听地址。只给反代用时可改 `127.0.0.1`                             |
| `DATABASE_PATH`              | `./data/toolbox.db` | SQLite 文件位置                                                    |
| `SESSION_TTL_DAYS`           | `30`                | 会话有效期（天）                                                   |
| `SESSION_RENEW_THROTTLE_MIN` | `5`                 | 续期写库的最小间隔（分钟）                                         |
| `TRUST_PROXY`                | `true`              | 在反向代理后面时保持 true，才能拿到真实客户端 IP                   |
| `LOG_LEVEL`                  | `info`              | `fatal` / `error` / `warn` / `info` / `debug` / `trace` / `silent` |
| `CREDENTIAL_KEY`             | 自动生成            | SSH 凭据加密密钥，至少 16 字符                                     |

### 关于 CREDENTIAL_KEY

SSH 服务器的密码和私钥在落盘前会用 AES-256-GCM 加密。

不设置时，程序会在数据库旁边生成 `.credential-key` 文件（权限 0600）并自动使用。**这个文件丢了，已存的凭据就解不开了**，备份数据库时请一并备份它。

想自己管理密钥：

```bash
export CREDENTIAL_KEY="至少十六个字符的随机串"
```

---

## 数据目录

容器里的 `/app/data` 挂载到 **compose.yml 所在目录**下的 `data/`：

| 部署方式           | 数据位置                                |
| ------------------ | --------------------------------------- |
| 方式一（拉镜像）   | `toolbox/data/`                         |
| 方式二（源码构建） | `tool-box/docker/data/`                 |
| 方式三（直接运行） | 由 `DATABASE_PATH` 决定，默认 `./data/` |

目录里有什么：

```
data/
  toolbox.db                    ← 数据库
  toolbox.db.v2-*.bak           ← 自动备份
  .credential-key               ← 加密密钥
```

**备份这个目录 = 备份全部数据。** 迁移到新机器时整个拷走即可。

---

## 反向代理

程序只监听 HTTP，域名、证书、HTTPS 都交给反向代理。

nginx 示例，要点是保留原始 Host 与客户端 IP：

```nginx
server {
    listen 443 ssl http2;
    server_name toolbox.example.com;

    ssl_certificate     /etc/letsencrypt/live/toolbox.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/toolbox.example.com/privkey.pem;

    client_max_body_size 100m;

    location / {
        proxy_pass http://127.0.0.1:7788;
        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        "upgrade";

        proxy_read_timeout 300s;
    }
}
```

`client_max_body_size` 要放大，因为 SFTP 上传会经过它。`proxy_read_timeout` 同理——大文件传输不能中途断开。

---

## 健康检查

```bash
curl http://127.0.0.1:7788/api/health
```

返回 `{"status":"ok","db":"ok"}` 表示正常。`db` 字段反映数据库是否可读。

---

## 首次启动

打开页面会要求注册。用户名和密码都由你定，注册完成后入口永久关闭。

**注册前请确认这个地址不会被别人访问到**——否则第一个访问的人就成了所有者。
