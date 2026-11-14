FROM node:24-alpine AS builder

RUN corepack enable pnpm
WORKDIR /app
ENV HUSKY=0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY tsconfig.json ./
COPY src/ ./src/
RUN pnpm run build

FROM node:24-alpine

# ca-certificates: system CA bundle + update-ca-certificates.
# su-exec: lets the entrypoint drop from root to the node user.
RUN corepack enable pnpm \
 && apk add --no-cache ca-certificates su-exec
WORKDIR /app
ENV HUSKY=0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod --ignore-scripts
COPY --from=builder /app/dist/ ./dist/

# The entrypoint installs custom CA certificates (mounted at
# /opt/custom-certificates) as root and then drops to the node user.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
 && mkdir -p /opt/custom-certificates /usr/local/share/ca-certificates

EXPOSE 3001
# No `USER node` here on purpose: the entrypoint needs root for
# update-ca-certificates and then runs the CMD as node via su-exec.

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3001/health || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "dist/http.js"]
