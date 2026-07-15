# Stage 1: Builder
FROM node:24 AS builder

WORKDIR /build

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY patches ./patches

RUN corepack enable pnpm && pnpm install --frozen-lockfile

COPY . .
RUN pnpm build

# Stage 2: Runtime
FROM node:24-alpine

WORKDIR /app

# Copy built artifacts from builder
COPY --from=builder /build/dist ./dist
COPY --from=builder /build/openclaw.mjs ./
COPY --from=builder /build/package.json ./

# Install runtime dependencies only (production)
RUN corepack enable pnpm && pnpm install --prod --frozen-lockfile

# Create non-root user
RUN addgroup -g 1000 openclaw && adduser -D -u 1000 -G openclaw openclaw
USER openclaw

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

EXPOSE 18789

CMD ["node", "dist/index.js", "gateway", "--bind", "0.0.0.0", "--port", "18789"]
