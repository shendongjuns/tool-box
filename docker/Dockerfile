# ---------- 构建阶段 ----------
FROM node:24-bookworm-slim AS build
WORKDIR /repo

RUN corepack enable && corepack prepare pnpm@11.28.5 --activate

# 先复制清单，命中依赖缓存
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY packages/contracts/package.json packages/contracts/
COPY packages/data/package.json packages/data/
COPY packages/api-client/package.json packages/api-client/
COPY apps/server/package.json apps/server/
COPY apps/web/package.json apps/web/

RUN pnpm install --frozen-lockfile

COPY tsconfig.base.json ./
COPY packages ./packages
COPY apps/server ./apps/server
COPY apps/web ./apps/web

RUN pnpm --filter @toolbox/web build \
 && pnpm --filter @toolbox/server build

# 只保留生产依赖
RUN pnpm install --frozen-lockfile --prod --filter @toolbox/server...

# ---------- 运行阶段 ----------
FROM node:24-bookworm-slim AS runtime
ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0 \
    DATABASE_PATH=/app/data/toolbox.db

WORKDIR /app
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --create-home toolbox

COPY --from=build --chown=toolbox:toolbox /repo/node_modules ./node_modules
COPY --from=build --chown=toolbox:toolbox /repo/apps/server/node_modules ./apps/server/node_modules
COPY --from=build --chown=toolbox:toolbox /repo/apps/server/dist ./apps/server/dist
COPY --from=build --chown=toolbox:toolbox /repo/apps/server/package.json ./apps/server/package.json
COPY --from=build --chown=toolbox:toolbox /repo/apps/web/dist ./apps/server/public

RUN mkdir -p /app/data && chown -R toolbox:toolbox /app/data
USER toolbox
WORKDIR /app/apps/server

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/api/health || exit 1

CMD ["node", "dist/index.js"]
