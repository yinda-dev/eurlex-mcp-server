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

RUN corepack enable pnpm \
    # ca-certificates provides update-ca-certificates and the system CA bundle;
    # su-exec lets the entrypoint drop from root to the node user after
    # installing certificates.
 && apk add --no-cache ca-certificates su-exec
WORKDIR /app
ENV HUSKY=0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod --ignore-scripts
COPY --from=builder /app/dist/ ./dist/

# Copy and prepare the entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    # Create the mount-point so the directory always exists even without a bind-mount
 && mkdir -p /opt/custom-certificates \
    # Ensure the entrypoint can write to the system CA directory (runs as root before dropping to node)
 && chmod 755 /usr/local/share/ca-certificates

EXPOSE 3001

# The entrypoint runs as root so it can install certificates, then execs the CMD as the node user.
# Note: USER node is intentionally omitted here so the script can
# call update-ca-certificates (requires root). The script itself drops privileges via exec "$@".
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3001/health || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "dist/http.js"]
