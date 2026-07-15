# Build stage
FROM node:24-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --prefer-offline

# Runtime stage
FROM node:24-alpine
WORKDIR /app
COPY package.json ./
COPY dist ./dist
COPY openclaw.mjs ./
COPY --from=builder /app/node_modules ./node_modules

# Create non-root user
RUN addgroup -g 1001 openclaw && adduser -D -u 1001 -G openclaw openclaw
USER openclaw

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

EXPOSE 18789

CMD ["node", "dist/index.js", "gateway", "--bind", "0.0.0.0", "--port", "18789"]
