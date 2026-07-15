#!/bin/bash
set -euo pipefail

# Phase 8 Deployment Script
# Deploys Docker image to homelab LXC 102
# Usage: ./deploy-homelab.sh <image-tag> [optional: target-host]

IMAGE_TAG="${1:-latest}"
HOMELAB_HOST="${2:-192.168.178.211}"
HOMELAB_CONTAINER="102"
REGISTRY="ghcr.io"
REPO="openclaw/openclaw"
IMAGE="${REGISTRY}/${REPO}:${IMAGE_TAG}"

echo "=== Phase 8 Homelab Deployment ==="
echo "Image: $IMAGE"
echo "Target: root@${HOMELAB_HOST} → LXC ${HOMELAB_CONTAINER}"
echo ""

# Step 1: Verify SSH access
echo "1. Verifying SSH access to Proxmox host..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"${HOMELAB_HOST}" "echo 'SSH OK'"; then
  echo "FATAL: SSH to ${HOMELAB_HOST} failed"
  exit 1
fi

# Step 2: Pull image in container
echo ""
echo "2. Pulling image in LXC ${HOMELAB_CONTAINER}..."
ssh root@"${HOMELAB_HOST}" "pct exec ${HOMELAB_CONTAINER} -- docker pull '${IMAGE}'" || {
  echo "ERROR: Failed to pull image"
  exit 1
}

# Step 3: Update docker-compose
echo ""
echo "3. Updating docker-compose.yml..."
ssh root@"${HOMELAB_HOST}" "pct exec ${HOMELAB_CONTAINER} -- bash << 'COMPOSE_EOF'
cd /opt/services
sed -i 's|image: ghcr.io/openclaw/openclaw:.*|image: '"${IMAGE}"'|g' docker-compose.yml
echo "Updated docker-compose.yml"
COMPOSE_EOF
"

# Step 4: Restart services
echo ""
echo "4. Restarting services (docker-compose up -d)..."
ssh root@"${HOMELAB_HOST}" "pct exec ${HOMELAB_CONTAINER} -- bash << 'RESTART_EOF'
cd /opt/services
docker-compose up -d openclaw
echo "Services restarted"
RESTART_EOF
"

# Step 5: Health check
echo ""
echo "5. Running health checks..."
HEALTH_OK=0
for i in {1..30}; do
  if ssh root@"${HOMELAB_HOST}" "pct exec ${HOMELAB_CONTAINER} -- docker exec openclaw curl -sf http://localhost:3000/health >/dev/null 2>&1"; then
    echo "✓ OpenClaw health check PASSED"
    HEALTH_OK=1
    break
  fi
  echo "  Attempt $i/30 - waiting for service..."
  sleep 2
done

if [ $HEALTH_OK -eq 0 ]; then
  echo "ERROR: Health check failed after 60 seconds"
  echo "Logs:"
  ssh root@"${HOMELAB_HOST}" "pct exec ${HOMELAB_CONTAINER} -- docker logs openclaw | tail -20"
  exit 1
fi

# Step 6: Verify all required services
echo ""
echo "6. Verifying all required services..."
ssh root@"${HOMELAB_HOST}" "pct exec ${HOMELAB_CONTAINER} -- bash << 'VERIFY_EOF'
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "postgres|redis|nginx|haproxy|openclaw"
VERIFY_EOF
"

echo ""
echo "=== ✅ Deployment Successful ==="
echo "Image deployed: $IMAGE"
echo "Services running on LXC ${HOMELAB_CONTAINER}"
echo "Access: https://homelab.hofernexus.ch (via nginx proxy)"
