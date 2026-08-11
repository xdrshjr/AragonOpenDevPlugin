# Spec 07: Verification & Rollback

## Purpose

Define the tiered post-deployment verification system and the failure handling mechanism including rollback capabilities.

## Verification Tiers

### Quick Verification (Default)

Fast checks that confirm services are running:

| # | Check | Method | Pass Criteria |
|---|-------|--------|---------------|
| 1 | Backend HTTP health | `curl -sf http://localhost:{{BACKEND_PORT}}/health` | HTTP 2xx |
| 2 | Frontend HTTP health | `curl -sf http://localhost:{{FRONTEND_PORT}}/` | HTTP 2xx |
| 3 | Service active state | `systemctl is-active {{PROJECT_NAME}}-*.service` | "active" |
| 4 | Port listening | `ss -tlnH sport = :{{PORT}}` | Port open |

For Docker mode:
| # | Check | Method | Pass Criteria |
|---|-------|--------|---------------|
| 1 | Container running | `docker compose ps --format json` | State = "running" |
| 2 | Container healthy | `docker inspect --format='{{.State.Health.Status}}'` | "healthy" |
| 3 | HTTP health endpoints | Same as systemd mode | HTTP 2xx |

### Full Verification

All quick checks plus:

| # | Check | Method | Pass Criteria |
|---|-------|--------|---------------|
| 5 | Nginx config valid | `nginx -t` | Exit 0 |
| 6 | Nginx serving | `curl -sf http://{{NGINX_DOMAIN}}/` | HTTP 2xx (via domain) |
| 7 | SSL certificate | `openssl s_client -connect {{DOMAIN}}:443` | Valid cert, not expired |
| 8 | Watchdog active | `systemctl is-active {{PROJECT_NAME}}-watchdog.timer` | "active" |
| 9 | Log output | `journalctl -u {{PROJECT_NAME}}-backend -n 5 --no-pager` | No ERROR lines |
| 10 | Disk space | `df -h {{PROJECT_DIR}}` | >10% free |
| 11 | Memory usage | `free -h` | >500MB available |
| 12 | Process resource | `ps aux \| grep {{PROJECT_NAME}}` | Reasonable CPU/MEM |

### Verification Report Format

```
╔══════════════════════════════════════════════════╗
║  Deployment Verification Report                   ║
║  Server: prod-1 (10.0.1.10)                     ║
║  Time: 2026-03-28T15:30:00Z                      ║
╠══════════════════════════════════════════════════╣
║  [✓] Backend health:     HTTP 200 OK              ║
║  [✓] Frontend health:    HTTP 200 OK              ║
║  [✓] Backend service:    active (running)          ║
║  [✓] Frontend service:   active (running)          ║
║  [✓] Port 5000:          listening                 ║
║  [✓] Port 3000:          listening                 ║
║  [✓] Nginx config:       valid                     ║
║  [✓] Domain reachable:   HTTP 200 via example.com  ║
║  [✓] SSL certificate:    valid, expires 2026-06-15  ║
║  [✓] Watchdog:           active                    ║
║  [✓] Logs:               no errors                 ║
║  [✓] Disk:               45G free (45%)            ║
║  [✓] Memory:             3.2G available             ║
╠══════════════════════════════════════════════════╣
║  Result: ALL CHECKS PASSED                        ║
╚══════════════════════════════════════════════════╝
```

## Pre-Deployment Backup

Before any deployment operation, create a backup:

### systemd Mode Backup

```bash
BACKUP_DIR="{{PROJECT_DIR}}/.deploy-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup current config
cp -r ops/config.env "$BACKUP_DIR/" 2>/dev/null || true

# Backup systemd units
cp /etc/systemd/system/{{PROJECT_NAME}}-*.service "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/systemd/system/{{PROJECT_NAME}}-*.timer "$BACKUP_DIR/" 2>/dev/null || true

# Backup Nginx config
cp /etc/nginx/sites-available/{{NGINX_SITE_NAME}} "$BACKUP_DIR/" 2>/dev/null || true

# Record current state
systemctl list-units '{{PROJECT_NAME}}-*' --no-pager > "$BACKUP_DIR/service-state.txt"

echo "$(date -Iseconds)" > "$BACKUP_DIR/backup.timestamp"
```

### Docker Mode Backup

```bash
BACKUP_DIR="{{PROJECT_DIR}}/.deploy-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup docker compose state
docker compose ps --format json > "$BACKUP_DIR/container-state.json" 2>/dev/null || true
cp docker-compose.yml "$BACKUP_DIR/" 2>/dev/null || true
cp Dockerfile* "$BACKUP_DIR/" 2>/dev/null || true

# Tag current images for rollback
docker compose images --format json | jq -r '.[].ID' | while read id; do
    docker tag "$id" "{{PROJECT_NAME}}-backup:$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
done
```

## Failure Handling

When any verification check fails:

### Step 1: Generate Failure Report

```
╔══════════════════════════════════════════════════╗
║  DEPLOYMENT VERIFICATION FAILED                   ║
╠══════════════════════════════════════════════════╣
║  Failed checks:                                   ║
║  [✗] Backend health: Connection refused            ║
║  [✗] Backend service: failed (exit-code)           ║
║                                                    ║
║  Diagnostic info:                                  ║
║  - Last 20 lines of backend journal log            ║
║  - Service status details                          ║
║  - Port conflict check results                     ║
╚══════════════════════════════════════════════════╝
```

### Step 2: User Decision

Ask via `AskUserQuestion`:

- Option 1: **"Retry deployment"** — Re-run the deployment pipeline from the build step
- Option 2: **"Rollback to previous state"** — Restore from backup
- Option 3: **"Show detailed logs and let me fix manually"** — Display diagnostic info
- Option 4: **"Skip this server and continue with others"** — (multi-server only)

### Step 3: Rollback Execution

If user chooses rollback:

**systemd rollback:**
1. Stop current services
2. Restore systemd units from backup
3. Restore Nginx config from backup
4. `systemctl daemon-reload`
5. Start services from backup units
6. Verify rollback succeeded

**Docker rollback:**
1. `docker compose down`
2. Restore docker-compose.yml from backup
3. Retag backup images
4. `docker compose up -d`
5. Verify rollback succeeded

## Backup Retention

Keep last 5 backups. Clean older ones:

```bash
ls -dt {{PROJECT_DIR}}/.deploy-backups/*/ | tail -n +6 | xargs rm -rf
```

## Multi-Server Verification

For batch deployments, run verification on all servers and produce a summary:

```
╔══════════════════════════════════════════════════╗
║  Multi-Server Verification Summary                ║
╠══════════════════════════════════════════════════╣
║  prod-1 (10.0.1.10):  ✓ ALL PASSED               ║
║  prod-2 (10.0.1.11):  ✓ ALL PASSED               ║
║  prod-3 (10.0.1.12):  ✗ FAILED (backend health)  ║
╚══════════════════════════════════════════════════╝
```

Failed servers are handled individually (retry/rollback/skip).
