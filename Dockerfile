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
COPY docker-entrypoint.sh /

# Create non-root user with home directory
RUN groupadd -g 1001 openclaw && useradd -u 1001 -g openclaw -m openclaw

# Fix app directory permissions
RUN chown -R openclaw:openclaw /app

# Make entrypoint executable
RUN chmod +x /docker-entrypoint.sh

# Health check (runs as root, that's fine)
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

EXPOSE 18789

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["node", "dist/index.js", "gateway", "--bind", "auto", "--port", "18789", "--allow-unconfigured"]
