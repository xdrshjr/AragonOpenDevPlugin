<!-- Section: Verification & Rollback -->
<!-- Author: dev-07 -->
<!-- Integrates into: SKILL.md Phase 7 -->
<!-- Consumed by: dev-08 (integrator) -->

### Phase 7: Post-Deployment Verification & Rollback

Run tiered health checks to verify deployment success. If verification fails, generate a diagnostic report and present rollback options. This phase runs after deployment (Phase 6A/6B) and Nginx configuration (Phase 6C).

#### Step 1: Select Verification Tier

In guided mode, ask the user:

```
AskUserQuestion:
  question: "Deployment execution complete. Select verification level:"
  candidates:
    - "Quick verification (health checks + service status — ~15 seconds)"
    - "Full verification (all checks including SSL, logs, resources — ~45 seconds)"
    - "Skip verification"
```

In auto mode, run full verification automatically.

If user selects "Skip verification", jump to Phase 8 (Summary).

#### Step 2: Quick Verification Checks

Run these checks on each target server. Each check produces a `PASS` or `FAIL` result.

**For systemd deployments:**

Execute via `ssh_exec`:

```bash
echo "=== Quick Verification ==="
RESULTS=""
FAILURES=0

# Check 1: Backend HTTP health
{{IF HAS_BACKEND}}
if curl -sf --max-time 10 "{{BACKEND_HEALTH_URL}}" > /dev/null 2>&1; then
    RESULTS="${RESULTS}[PASS] Backend health: HTTP 200 OK\n"
else
    # Fallback URL
    if curl -sf --max-time 10 "{{BACKEND_HEALTH_FALLBACK_URL}}" > /dev/null 2>&1; then
        RESULTS="${RESULTS}[PASS] Backend health: HTTP 200 OK (fallback URL)\n"
    else
        RESULTS="${RESULTS}[FAIL] Backend health: not responding\n"
        FAILURES=$((FAILURES + 1))
    fi
fi
{{ENDIF HAS_BACKEND}}

# Check 2: Frontend HTTP health
{{IF HAS_FRONTEND}}
if curl -sf --max-time 10 "{{FRONTEND_HEALTH_URL}}" > /dev/null 2>&1; then
    RESULTS="${RESULTS}[PASS] Frontend health: HTTP 200 OK\n"
else
    RESULTS="${RESULTS}[FAIL] Frontend health: not responding\n"
    FAILURES=$((FAILURES + 1))
fi
{{ENDIF HAS_FRONTEND}}

# Check 3: Backend service active
{{IF HAS_BACKEND}}
BACKEND_STATE=$(systemctl is-active "{{PROJECT_NAME}}-backend.service" 2>/dev/null || echo "not-found")
if [ "$BACKEND_STATE" = "active" ]; then
    RESULTS="${RESULTS}[PASS] Backend service: active (running)\n"
else
    RESULTS="${RESULTS}[FAIL] Backend service: $BACKEND_STATE\n"
    FAILURES=$((FAILURES + 1))
fi
{{ENDIF HAS_BACKEND}}

# Check 4: Frontend service active
{{IF HAS_FRONTEND}}
FRONTEND_STATE=$(systemctl is-active "{{PROJECT_NAME}}-frontend.service" 2>/dev/null || echo "not-found")
if [ "$FRONTEND_STATE" = "active" ]; then
    RESULTS="${RESULTS}[PASS] Frontend service: active (running)\n"
else
    RESULTS="${RESULTS}[FAIL] Frontend service: $FRONTEND_STATE\n"
    FAILURES=$((FAILURES + 1))
fi
{{ENDIF HAS_FRONTEND}}

# Check 5: Backend port listening
{{IF HAS_BACKEND}}
if ss -tlnH "sport = :{{BACKEND_PORT}}" | grep -q "{{BACKEND_PORT}}"; then
    RESULTS="${RESULTS}[PASS] Port {{BACKEND_PORT}}: listening\n"
else
    RESULTS="${RESULTS}[FAIL] Port {{BACKEND_PORT}}: not listening\n"
    FAILURES=$((FAILURES + 1))
fi
{{ENDIF HAS_BACKEND}}

# Check 6: Frontend port listening
{{IF HAS_FRONTEND}}
if ss -tlnH "sport = :{{FRONTEND_PORT}}" | grep -q "{{FRONTEND_PORT}}"; then
    RESULTS="${RESULTS}[PASS] Port {{FRONTEND_PORT}}: listening\n"
else
    RESULTS="${RESULTS}[FAIL] Port {{FRONTEND_PORT}}: not listening\n"
    FAILURES=$((FAILURES + 1))
fi
{{ENDIF HAS_FRONTEND}}

echo -e "$RESULTS"
echo "FAILURES=$FAILURES"
```

**For Docker deployments:**

```bash
echo "=== Quick Verification (Docker) ==="
RESULTS=""
FAILURES=0

cd "{{PROJECT_DIR}}"

# Check 1: Containers running
RUNNING_COUNT=$(docker compose ps --status running -q 2>/dev/null | wc -l)
EXPECTED_COUNT=$(docker compose ps -q 2>/dev/null | wc -l)
if [ "$RUNNING_COUNT" -eq "$EXPECTED_COUNT" ] && [ "$EXPECTED_COUNT" -gt 0 ]; then
    RESULTS="${RESULTS}[PASS] Containers: ${RUNNING_COUNT}/${EXPECTED_COUNT} running\n"
else
    RESULTS="${RESULTS}[FAIL] Containers: ${RUNNING_COUNT}/${EXPECTED_COUNT} running\n"
    FAILURES=$((FAILURES + 1))
fi

# Check 2: Container health status
for container_id in $(docker compose ps -q 2>/dev/null); do
    name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
    health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")
    if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
        RESULTS="${RESULTS}[PASS] Container $name: $health\n"
    else
        RESULTS="${RESULTS}[FAIL] Container $name: $health\n"
        FAILURES=$((FAILURES + 1))
    fi
done

# Check 3: HTTP health endpoints
{{IF HAS_BACKEND}}
if curl -sf --max-time 10 "http://localhost:{{BACKEND_PORT}}/health" > /dev/null 2>&1; then
    RESULTS="${RESULTS}[PASS] Backend HTTP: OK\n"
else
    RESULTS="${RESULTS}[FAIL] Backend HTTP: not responding\n"
    FAILURES=$((FAILURES + 1))
fi
{{ENDIF HAS_BACKEND}}

{{IF HAS_FRONTEND}}
if curl -sf --max-time 10 "http://localhost:{{FRONTEND_PORT}}/" > /dev/null 2>&1; then
    RESULTS="${RESULTS}[PASS] Frontend HTTP: OK\n"
else
    RESULTS="${RESULTS}[FAIL] Frontend HTTP: not responding\n"
    FAILURES=$((FAILURES + 1))
fi
{{ENDIF HAS_FRONTEND}}

echo -e "$RESULTS"
echo "FAILURES=$FAILURES"
```

#### Step 3: Full Verification Checks (Additional)

These checks run only if the user selected "Full verification". They extend the quick checks from Step 2.

```bash
echo "=== Full Verification (Extended) ==="

# Check 7: Nginx config valid
if command -v nginx > /dev/null 2>&1; then
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        RESULTS="${RESULTS}[PASS] Nginx config: valid\n"
    else
        RESULTS="${RESULTS}[FAIL] Nginx config: invalid\n"
        FAILURES=$((FAILURES + 1))
    fi
else
    RESULTS="${RESULTS}[SKIP] Nginx: not installed\n"
fi

# Check 8: Nginx serving domain
if [ -n "{{NGINX_DOMAIN}}" ]; then
    PRIMARY_DOMAIN=$(echo "{{NGINX_DOMAIN}}" | awk '{print $1}')
    if curl -sf --max-time 10 "http://${PRIMARY_DOMAIN}/" > /dev/null 2>&1; then
        RESULTS="${RESULTS}[PASS] Domain reachable: HTTP 200 via ${PRIMARY_DOMAIN}\n"
    elif curl -sf --max-time 10 "http://localhost/" -H "Host: ${PRIMARY_DOMAIN}" > /dev/null 2>&1; then
        RESULTS="${RESULTS}[PASS] Domain reachable: HTTP 200 via localhost (DNS may not have propagated)\n"
    else
        RESULTS="${RESULTS}[FAIL] Domain not reachable: ${PRIMARY_DOMAIN}\n"
        FAILURES=$((FAILURES + 1))
    fi
fi

# Check 9: SSL certificate
{{IF HAS_SSL}}
if [ -n "{{NGINX_DOMAIN}}" ]; then
    PRIMARY_DOMAIN=$(echo "{{NGINX_DOMAIN}}" | awk '{print $1}')
    SSL_INFO=$(echo | openssl s_client -connect "${PRIMARY_DOMAIN}:443" -servername "${PRIMARY_DOMAIN}" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    if [ -n "$SSL_INFO" ]; then
        EXPIRY=$(echo "$SSL_INFO" | grep "notAfter" | cut -d= -f2)
        RESULTS="${RESULTS}[PASS] SSL certificate: valid, expires ${EXPIRY}\n"
    else
        # Try via localhost
        SSL_INFO=$(echo | openssl s_client -connect "localhost:443" -servername "${PRIMARY_DOMAIN}" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
        if [ -n "$SSL_INFO" ]; then
            EXPIRY=$(echo "$SSL_INFO" | grep "notAfter" | cut -d= -f2)
            RESULTS="${RESULTS}[PASS] SSL certificate: valid, expires ${EXPIRY} (checked via localhost)\n"
        else
            RESULTS="${RESULTS}[FAIL] SSL certificate: could not verify\n"
            FAILURES=$((FAILURES + 1))
        fi
    fi
fi
{{ENDIF HAS_SSL}}

# Check 10: Watchdog active (systemd only)
# NOTE: The SKILL selects which block to send via ssh_exec based on deploy_mode at runtime.
# --- systemd mode ---
WATCHDOG_STATE=$(systemctl is-active "{{PROJECT_NAME}}-watchdog.timer" 2>/dev/null || echo "not-found")
if [ "$WATCHDOG_STATE" = "active" ]; then
    NEXT_RUN=$(systemctl show "{{PROJECT_NAME}}-watchdog.timer" --property=NextElapseUSecRealtime --value 2>/dev/null || echo "unknown")
    RESULTS="${RESULTS}[PASS] Watchdog timer: active (next: ${NEXT_RUN})\n"
else
    RESULTS="${RESULTS}[FAIL] Watchdog timer: $WATCHDOG_STATE\n"
    FAILURES=$((FAILURES + 1))
fi

# Check 11: Recent error logs
# --- systemd mode ---
{{IF HAS_BACKEND}}
ERROR_COUNT=$(journalctl -u "{{PROJECT_NAME}}-backend.service" -n 50 --no-pager 2>/dev/null | grep -ci "error\|traceback\|exception" || echo "0")
if [ "$ERROR_COUNT" -eq 0 ]; then
    RESULTS="${RESULTS}[PASS] Backend logs: no recent errors\n"
else
    RESULTS="${RESULTS}[WARN] Backend logs: ${ERROR_COUNT} error lines in last 50 entries\n"
fi
{{ENDIF HAS_BACKEND}}

# --- docker mode (alternative for Check 11 — SKILL sends this block instead when deploy_mode == "docker") ---
# ERROR_COUNT=$(docker compose logs --tail 50 2>/dev/null | grep -ci "error\|traceback\|exception" || echo "0")
# if [ "$ERROR_COUNT" -eq 0 ]; then
#     RESULTS="${RESULTS}[PASS] Container logs: no recent errors\n"
# else
#     RESULTS="${RESULTS}[WARN] Container logs: ${ERROR_COUNT} error lines in last 50 entries\n"
# fi

# Check 12: Disk space
DISK_AVAIL=$(df -h "{{PROJECT_DIR}}" | tail -1 | awk '{print $4}')
DISK_PCT=$(df "{{PROJECT_DIR}}" | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$DISK_PCT" -lt 90 ]; then
    RESULTS="${RESULTS}[PASS] Disk space: ${DISK_AVAIL} available (${DISK_PCT}% used)\n"
else
    RESULTS="${RESULTS}[WARN] Disk space: ${DISK_AVAIL} available (${DISK_PCT}% used — LOW)\n"
fi

# Check 13: Memory
MEM_AVAIL=$(free -h | awk '/^Mem:/{print $7}')
MEM_AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
if [ "$MEM_AVAIL_MB" -gt 500 ]; then
    RESULTS="${RESULTS}[PASS] Memory: ${MEM_AVAIL} available\n"
else
    RESULTS="${RESULTS}[WARN] Memory: ${MEM_AVAIL} available — LOW\n"
fi

echo -e "$RESULTS"
echo "FAILURES=$FAILURES"
```

#### Step 4: Format Verification Report

Present the verification results in a structured report. Use the language selected in Phase 1.

**English report format:**

```
╔══════════════════════════════════════════════════════╗
║  Deployment Verification Report                       ║
║  Server: {{SERVER_HOST}} ({{REMOTE_DIR}})            ║
║  Time:   {{TIMESTAMP}}                                ║
║  Mode:   {{DEPLOY_MODE}}                              ║
╠══════════════════════════════════════════════════════╣
║  {{RESULTS — each line from the checks above}}        ║
╠══════════════════════════════════════════════════════╣
║  Result: {{ALL CHECKS PASSED / N CHECKS FAILED}}     ║
╚══════════════════════════════════════════════════════╝
```

**Chinese report format:**

```
╔══════════════════════════════════════════════════════╗
║  部署验证报告                                          ║
║  服务器: {{SERVER_HOST}} ({{REMOTE_DIR}})             ║
║  时间:   {{TIMESTAMP}}                                ║
║  模式:   {{DEPLOY_MODE}}                              ║
╠══════════════════════════════════════════════════════╣
║  {{结果 — 每行检查结果}}                               ║
╠══════════════════════════════════════════════════════╣
║  结果: {{全部通过 / N 项检查失败}}                      ║
╚══════════════════════════════════════════════════════╝
```

If all checks passed, proceed to Phase 8 (Summary & Handoff).

If any checks failed, proceed to Step 5 (Failure Handling).

#### Step 5: Failure Report Generation

When verification detects failures, collect diagnostic information before presenting options to the user:

```bash
echo "=== Diagnostic Information ==="

# Service status details
{{IF DEPLOY_MODE_SYSTEMD}}
{{IF HAS_BACKEND}}
echo "--- Backend Service Status ---"
systemctl status "{{PROJECT_NAME}}-backend.service" --no-pager 2>/dev/null || true
echo ""
echo "--- Backend Journal (last 30 lines) ---"
journalctl -u "{{PROJECT_NAME}}-backend.service" -n 30 --no-pager 2>/dev/null || true
{{ENDIF HAS_BACKEND}}

{{IF HAS_FRONTEND}}
echo ""
echo "--- Frontend Service Status ---"
systemctl status "{{PROJECT_NAME}}-frontend.service" --no-pager 2>/dev/null || true
echo ""
echo "--- Frontend Journal (last 30 lines) ---"
journalctl -u "{{PROJECT_NAME}}-frontend.service" -n 30 --no-pager 2>/dev/null || true
{{ENDIF HAS_FRONTEND}}
{{ENDIF DEPLOY_MODE_SYSTEMD}}

{{IF DEPLOY_MODE_DOCKER}}
echo "--- Docker Container Status ---"
docker compose ps 2>/dev/null || true
echo ""
echo "--- Container Logs (last 30 lines) ---"
docker compose logs --tail 30 2>/dev/null || true
{{ENDIF DEPLOY_MODE_DOCKER}}

# Port conflict check
echo ""
echo "--- Port Usage ---"
ss -tlnp "sport = :{{BACKEND_PORT}} or sport = :{{FRONTEND_PORT}}" 2>/dev/null || true

# Nginx error log
if [ -n "{{NGINX_DOMAIN}}" ]; then
    echo ""
    echo "--- Nginx Error Log (last 10 lines) ---"
    sudo tail -10 /var/log/nginx/error.log 2>/dev/null || true
fi
```

Present the failure report with diagnostic info and ask the user for a decision:

```
AskUserQuestion:
  question: |
    Deployment verification FAILED on {{SERVER_HOST}}.

    Failed checks:
    {{FAILED_CHECK_LINES}}

    Diagnostic summary:
    {{DIAGNOSTIC_SUMMARY — condensed to key error lines}}

    What would you like to do?
  candidates:
    - "Retry deployment (re-run from build step)"
    - "Rollback to previous state"
    - "Show detailed logs and let me fix manually"
    - "Skip this server and continue with others"  # multi-server only
```

#### Step 6: Retry Deployment

If the user selects "Retry deployment":
1. Go back to Phase 6 Step 3 (Project Build) — skip dependency installation since deps are already installed
2. Re-run the build, service install, and service start sequence
3. Re-run verification after retry
4. Maximum 2 retries — after that, force a decision between rollback and manual fix

#### Step 7: Rollback Execution (systemd)

If the user selects "Rollback to previous state" and the deployment mode is systemd:

```bash
# Find the most recent backup
BACKUP_DIR=$(ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ 2>/dev/null | head -1)

if [ -z "$BACKUP_DIR" ]; then
    echo "ERROR: No backup found — cannot rollback"
    exit 1
fi

echo "Rolling back from: $BACKUP_DIR"

# Step 1: Stop current services
systemctl stop "{{PROJECT_NAME}}-watchdog.timer"     2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-watchdog.service"   2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-frontend.service"   2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-backend.service"    2>/dev/null || true

# Step 2: Restore systemd unit files
cp "$BACKUP_DIR"/{{PROJECT_NAME}}-*.service /etc/systemd/system/ 2>/dev/null || true
cp "$BACKUP_DIR"/{{PROJECT_NAME}}-*.timer /etc/systemd/system/ 2>/dev/null || true

# Step 3: Restore Nginx config
if [ -f "$BACKUP_DIR/{{NGINX_SITE_NAME}}" ]; then
    cp "$BACKUP_DIR/{{NGINX_SITE_NAME}}" "/etc/nginx/sites-available/{{NGINX_SITE_NAME}}"
    sudo nginx -t 2>&1 && sudo systemctl reload nginx
fi

# Step 4: Restore config.env
if [ -f "$BACKUP_DIR/config.env" ]; then
    cp "$BACKUP_DIR/config.env" "{{PROJECT_DIR}}/ops/config.env"
fi

# Step 5: Reload and restart
systemctl daemon-reload
systemctl start "{{PROJECT_NAME}}-backend.service"  2>/dev/null || true
systemctl start "{{PROJECT_NAME}}-frontend.service" 2>/dev/null || true
systemctl start "{{PROJECT_NAME}}-watchdog.timer"   2>/dev/null || true

echo "Rollback complete — services restored from backup"
```

After rollback, run quick verification again to confirm the previous state is restored.

#### Step 8: Rollback Execution (Docker)

If the deployment mode is Docker:

```bash
BACKUP_DIR=$(ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ 2>/dev/null | head -1)

if [ -z "$BACKUP_DIR" ]; then
    echo "ERROR: No backup found — cannot rollback"
    exit 1
fi

echo "Rolling back from: $BACKUP_DIR"

cd "{{PROJECT_DIR}}"

# Step 1: Stop current containers
docker compose down 2>/dev/null || true

# Step 2: Restore docker-compose.yml
cp "$BACKUP_DIR"/docker-compose.yml "{{PROJECT_DIR}}/" 2>/dev/null || true
cp "$BACKUP_DIR"/Dockerfile* "{{PROJECT_DIR}}/" 2>/dev/null || true

# Step 3: Restore Nginx config
if [ -f "$BACKUP_DIR/{{NGINX_SITE_NAME}}" ]; then
    cp "$BACKUP_DIR/{{NGINX_SITE_NAME}}" "/etc/nginx/sites-available/{{NGINX_SITE_NAME}}"
    sudo nginx -t 2>&1 && sudo systemctl reload nginx
fi

# Step 4: Restart with restored config
docker compose up -d

echo "Rollback complete — containers restored from backup"
```

#### Step 9: Manual Fix Mode

If the user selects "Show detailed logs and let me fix manually":

1. Display the full diagnostic output (service status, journal logs, port info, Nginx errors)
2. Suggest the SSH command for manual access:

```
You can connect to the server for manual debugging:
  ssh {{RUN_USER}}@{{SERVER_HOST}}

Useful commands:
  systemctl status {{PROJECT_NAME}}-backend.service
  journalctl -u {{PROJECT_NAME}}-backend.service -f
  sudo nginx -t
  cat {{PROJECT_DIR}}/ops/config.env
```

3. After the user has fixed the issue, offer to re-run verification:

```
AskUserQuestion:
  question: "Have you finished the manual fix? Would you like me to re-run verification?"
  candidates:
    - "Yes, run verification again"
    - "Done, proceed to summary"
```

#### Step 10: Multi-Server Verification Summary

For batch deployments (multiple servers), run verification on all servers and produce an aggregated summary:

```
╔══════════════════════════════════════════════════════╗
║  Multi-Server Verification Summary                    ║
╠══════════════════════════════════════════════════════╣
║  prod-1 (10.0.1.10):  ✓ ALL PASSED (12/12)          ║
║  prod-2 (10.0.1.11):  ✓ ALL PASSED (12/12)          ║
║  prod-3 (10.0.1.12):  ✗ FAILED (2/12 failed)        ║
║                         - Backend health: not responding║
║                         - Backend service: failed      ║
╠══════════════════════════════════════════════════════╣
║  Total: 2/3 servers fully deployed                    ║
╚══════════════════════════════════════════════════════╝
```

For each failed server, present the failure handling options (Step 5) individually.

In auto mode, failed servers are reported at the end without interactive prompts — the user can re-run the skill targeting only the failed servers.

#### Step 11: Backup Retention

After successful verification (all checks passed), clean up old backups to save disk space. Keep the 5 most recent backups:

```bash
ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true
echo "Old backups cleaned (kept last 5)"
```

---

**Phase 7 output gate:** Verification must produce one of these outcomes:
1. **ALL PASSED** — proceed to Phase 8 (Summary)
2. **FAILED + Rollback succeeded** — proceed to Phase 8 with rollback note
3. **FAILED + Manual fix applied** — proceed to Phase 8 with manual fix note
4. **FAILED + User skipped** — proceed to Phase 8 with warning
