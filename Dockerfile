FROM node:24.5-alpine AS builder

RUN apk upgrade --no-cache zlib
RUN corepack enable pnpm
WORKDIR /app
ENV HUSKY=0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY tsconfig.json ./
COPY src/ ./src/
RUN pnpm run build
# Separate, clean prod-only install into a dedicated directory
RUN mkdir /prod_modules && \
    cp package.json pnpm-lock.yaml /prod_modules/ && \
    cd /prod_modules && \
    pnpm install --frozen-lockfile --prod --ignore-scripts

FROM node:24.5-alpine

RUN apk upgrade --no-cache zlib

# Install ca-certificates so update-ca-certificates is available for
# custom CA injection at container startup via docker-entrypoint.sh
RUN apk add --no-cache ca-certificates

RUN rm -rf /usr/local/lib/node_modules/npm \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx
WORKDIR /app
ENV HUSKY=0

# Node 24.5+ natively honours HTTP_PROXY / HTTPS_PROXY / NO_PROXY for the
# built-in fetch() via the NODE_USE_ENV_PROXY flag introduced in Node 22.
# Set it here so callers can pass -e HTTPS_PROXY=... at docker run time without
# needing any third-party proxy package.
ENV NODE_USE_ENV_PROXY=1

COPY --from=builder /prod_modules/node_modules/ ./node_modules/
COPY --from=builder /app/dist/ ./dist/

# Copy and prepare the entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    # Create the mount-point so the directory always exists even without a bind-mount
 && mkdir -p /opt/custom-certificates \
    # Ensure the entrypoint can write to the system CA directory (runs as root before dropping to node)
 && chmod 755 /usr/local/share/ca-certificates

EXPOSE 3001


HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3001/health || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "dist/http.js"]
