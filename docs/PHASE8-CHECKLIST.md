# Phase 8 Implementation Checklist

## Pre-Deployment Setup

### GitHub Secrets Configuration

- [ ] Add `HOMELAB_SSH_KEY` secret
  - Value: contents of `~/.ssh/id_ed25519` (private key)
  - Verify: `ssh -i ~/.ssh/id_ed25519 root@192.168.178.211 "echo OK"`

- [ ] Add `HOMELAB_HOST` secret (optional, defaults to 192.168.178.211)
  - Value: `192.168.178.211`

- [ ] Add `HOMELAB_CONTAINER` secret (optional, defaults to 102)
  - Value: `102`

- [ ] Verify GitHub Container Registry (GHCR) access
  - Token: Use `secrets.GITHUB_TOKEN` (auto-managed)
  - No manual setup needed

### OpenClaw Dockerfile

- [ ] Create `Dockerfile` in OpenClaw root
  - Copy content from `/tmp/Dockerfile.openclaw`
  - Adjust startup command if needed (currently `pnpm start`)
  - Verify health check endpoint exists at `/health`

### GitHub Actions Workflow

- [ ] Create `.github/workflows/deploy-homelab.yml`
  - Copy content from `/tmp/deploy-homelab.yml`
  - Place in openclaw/.github/workflows/

### Deployment Script (Optional, for manual deploys)

- [ ] Create `scripts/deploy-homelab.sh`
  - Copy content from `/tmp/deploy-homelab.sh`
  - Make executable: `chmod +x scripts/deploy-homelab.sh`
  - Used for local testing before main merge

### LXC 102 docker-compose.yml Update

- [ ] Add OpenClaw service to `/opt/services/docker-compose.yml`

```yaml
openclaw:
  image: ghcr.io/openclaw/openclaw:latest
  container_name: openclaw
  ports:
    - "3000:3000"
  environment:
    - NODE_ENV=production
    - OPENCLAW_CONFIG=/etc/openclaw/config.json
    - LOG_LEVEL=info
  volumes:
    - /opt/openclaw/config.json:/etc/openclaw/config.json:ro
    - /opt/openclaw/state:/app/state
  depends_on:
    - postgres
    - redis
  restart: always
  networks:
    - services
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
```

### OpenClaw Health Check Endpoint

- [ ] Ensure `/health` endpoint exists (GET /health → 200 OK)
  - Response format: `{ status: 'ok', timestamp: '...' }`
  - Add to src/cli if missing

### Config & Mount Points

- [ ] Create `/opt/openclaw/config.json` on LXC 102
  - Database: `host=postgres:5432, user=dbuser, password=dbpass123`
  - Redis: `host=redis:6379`
  - Port: `3000`

- [ ] Create `/opt/openclaw/state` directory
  - OpenClaw state/db storage
  - Mounted read-write in container

### nginx Reverse Proxy (Optional)

- [ ] Add OpenClaw route to nginx.conf
  ```
  location /openclaw {
    proxy_pass http://openclaw:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
  ```

---

## Deployment Testing

### Local Build & Test

- [ ] Build Docker image locally
  ```bash
  docker build -f Dockerfile -t openclaw:test .
  docker run -p 3000:3000 openclaw:test
  curl http://localhost:3000/health
  ```

### Manual Deployment (Test)

- [ ] Run deployment script
  ```bash
  ./scripts/deploy-homelab.sh latest 192.168.178.211
  ```

  - Expected: "✅ Deployment Successful"

### Automated Deployment (First Push)

- [ ] Commit Dockerfile + workflow to branch
- [ ] Push to main (not PR)
- [ ] Watch GitHub Actions: Settings → Actions → Deploy to Homelab
- [ ] Verify:
  - [ ] Build & push to ghcr.io succeeds
  - [ ] SSH deploy to homelab succeeds
  - [ ] Health checks pass
  - [ ] Services restart without errors

### Verification Checklist

- [ ] Container running: `docker ps | grep openclaw`
- [ ] Health endpoint: `curl https://homelab.hofernexus.ch/openclaw/health`
- [ ] Logs: `docker logs openclaw | tail -20`
- [ ] Database connectivity: logs show no connection errors
- [ ] Redis connectivity: logs show cache available

---

## Rollback Procedure

### If Deployment Fails

1. **Stop problematic container:**

   ```bash
   ssh root@192.168.178.211
   pct exec 102 -- docker stop openclaw
   ```

2. **Revert docker-compose to last known good:**

   ```bash
   pct exec 102 -- git -C /opt/services checkout docker-compose.yml
   docker-compose up -d
   ```

3. **Inspect logs:**

   ```bash
   docker logs openclaw | tail -50
   ```

4. **Manually restart (if safe):**
   ```bash
   docker-compose up -d openclaw
   ```

---

## Post-Deployment Monitoring

### Daily Checks

- [ ] Container still running: `docker ps | grep openclaw`
- [ ] No error logs: `docker logs openclaw --since 24h | grep ERROR`
- [ ] Health endpoint responding: `curl https://homelab.hofernexus.ch/openclaw/health`

### Weekly Maintenance

- [ ] Disk space: `df -h /var/lib/docker`
- [ ] Image cleanup: `docker image prune --all --force`
- [ ] Log rotation configured

### Monthly Reviews

- [ ] Update phase8_cicd_plan.md with actual findings
- [ ] Plan for Phase 9+ (auto-scaling, disaster recovery)

---

## Secrets Rotation Schedule

### Quarterly (every 90 days)

- [ ] Rotate `HOMELAB_SSH_KEY` in GitHub Secrets
  - Generate new ED25519 key
  - Update ~/.ssh/authorized_keys on Proxmox
  - Update GitHub secret
  - Test deployment before deleting old key

### Annual

- [ ] Review all GHCR tokens
- [ ] Audit GitHub Actions logs for failed deployments

---

## Success Criteria

All of the following must pass:

- [ ] Docker image builds without errors
- [ ] Image pushed to ghcr.io/openclaw/openclaw
- [ ] SSH connection to homelab succeeds
- [ ] Docker image pulled in LXC 102
- [ ] docker-compose.yml updated with new image tag
- [ ] Container starts successfully
- [ ] Health check endpoint responds 200 OK
- [ ] All required services running (postgres, redis, nginx, haproxy, openclaw)
- [ ] Logs show no errors or critical warnings
- [ ] Application responds to requests via reverse proxy
