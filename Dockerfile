# Build stage
FROM node:24 AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY scripts ./scripts
COPY patches ./patches
RUN corepack enable pnpm && pnpm install

# Runtime stage
FROM node:24
WORKDIR /app
COPY package.json ./
COPY dist ./dist
COPY openclaw.mjs ./
COPY --from=builder /app/node_modules ./node_modules

# Create non-root user
RUN groupadd -g 1001 openclaw && useradd -u 1001 -g openclaw openclaw
USER openclaw

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

EXPOSE 18789

CMD ["node", "dist/index.js", "gateway", "--bind", "auto", "--port", "18789", "--allow-unconfigured"]
