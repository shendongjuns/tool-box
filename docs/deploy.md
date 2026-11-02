# 部署

两种方式：Docker 或者直接跑 Node 进程。前者省心，后者透明。

## 共同前提

程序只监听 HTTP，**不处理后端域名、证书、HTTPS**。这些交给反向代理。

它默认绑 `127.0.0.1`，也就是只有本机能连。想让局域网访问，有两个办法：

- 把 `HOST` 改成 `0.0.0.0`（配合防火墙）
- 或者用反向代理监听外网，转发到本机的 7788

第二种更安全，推荐。

## Docker

```bash
git clone https://github.com/shendongjuns/tool-box.git
cd tool-box/docker
docker compose up -d --build
```

`compose.yml` 已经配好：

| 项       | 值                         |
| -------- | -------------------------- |
| 端口映射 | `127.0.0.1:7788:7788`      |
| 数据卷   | `./data:/app/data`         |
| 健康检查 | 每 30 秒请求 `/api/health` |
| 重启策略 | `unless-stopped`           |

**要局域网访问**，把端口映射改成 `"7788:7788"`，然后重启。

数据在宿主机的 `docker/data/` 里，重建容器不影响。

查看日志：

```bash
docker compose logs -f toolbox
```

## 直接运行

需要 Node.js 22.12+ 与 pnpm 11+。

```bash
git clone https://github.com/shendongjuns/tool-box.git
cd tool-box

pnpm install
pnpm build
cd apps/server
node dist/index.js
```

或者用 pnpm：

```bash
pnpm --filter @toolbox/server start
```

## 配置

复制 `.env.example` 为 `.env`，按需修改。

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

不设置这个变量时，程序会在数据库旁边生成 `.credential-key` 文件（权限 0600）并自动使用。**这个文件丢了，已存的凭据就解不开了**，所以备份数据库时请一并备份它。

想自己管理密钥的话：

```bash
export CREDENTIAL_KEY="至少十六个字符的随机串"
```

## 反向代理

下面是 nginx 的示例。要点是保留原始 Host 与客户端 IP，否则 CSRF 校验会拒绝请求。

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

`client_max_body_size` 需要放大，因为 SFTP 上传会经过它。`proxy_read_timeout` 同理——大文件传输不能中途断开。

## 健康检查

```bash
curl http://127.0.0.1:7788/api/health
```

返回 `{"status":"ok","db":"ok"}` 表示正常。`db` 字段反映数据库是否可读。

## 首次启动

打开页面会要求注册。用户名和密码都由你定，注册完成后入口永久关闭。

**注册前请确认这个地址不会被别人访问到**——否则第一个访问的人就成了所有者。
