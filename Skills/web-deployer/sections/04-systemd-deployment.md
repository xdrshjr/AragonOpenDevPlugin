<!-- Section: systemd Deployment Pipeline -->
<!-- Author: dev-05 -->
<!-- Integrates into: SKILL.md Phase 6 (systemd path) -->
<!-- Consumed by: dev-07 (verification), dev-08 (integrator) -->

### Phase 6A: systemd Deployment Execution

Execute the systemd deployment pipeline on each target server. This phase runs after templates have been rendered (Phase 5) and uploaded to the server. All remote commands use the SSH helpers from Phase 3 (`ssh_exec`, `ssh_exec_long`, `sftp_upload`).

> **Prerequisite check**: Before executing any step, confirm these are true:
> - SSH connection to the target server is alive (call `ensure_connected()`)
> - `ops/` directory has been uploaded to `{{PROJECT_DIR}}/ops/` on the server
> - `config.env` has been rendered with server-specific values and uploaded

#### Step 1: Pre-Deployment Backup

Before modifying anything on the server, create a timestamped backup of the current state. This backup is consumed by the rollback logic in Phase 7.

Execute via `ssh_exec`:

```bash
BACKUP_DIR="{{PROJECT_DIR}}/.deploy-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup current config
cp -r "{{PROJECT_DIR}}/ops/config.env" "$BACKUP_DIR/" 2>/dev/null || true

# Backup systemd units
cp /etc/systemd/system/{{PROJECT_NAME}}-*.service "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/systemd/system/{{PROJECT_NAME}}-*.timer "$BACKUP_DIR/" 2>/dev/null || true

# Backup Nginx config
cp "/etc/nginx/sites-available/{{NGINX_SITE_NAME}}" "$BACKUP_DIR/" 2>/dev/null || true

# Record current service state
systemctl list-units '{{PROJECT_NAME}}-*' --no-pager > "$BACKUP_DIR/service-state.txt" 2>/dev/null || true

# Timestamp marker
echo "$(date -Iseconds)" > "$BACKUP_DIR/backup.timestamp"

# Cleanup old backups — keep last 5
ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true

echo "Backup created: $BACKUP_DIR"
```

Record the `BACKUP_DIR` path — it will be needed if rollback is triggered.

#### Step 2: Dependency Installation

Execute the rendered `install-deps.sh` on the server. Use `ssh_exec_long` because dependency installation can take several minutes (especially `npm install` with native modules).

```bash
cd "{{PROJECT_DIR}}" && chmod +x ops/install-deps.sh && bash ops/install-deps.sh
```

**Expected behavior by project type:**

| Project Type | What install-deps.sh Does |
|---|---|
| Python backend | Creates/activates virtualenv, runs `pip install -r requirements.txt` (or pipenv/poetry/conda equivalent) |
| Node.js project | Runs `npm install` (or yarn/pnpm), `npm rebuild` for native modules |
| Fullstack | Both Python and Node.js dependency chains |
| Conda environment | Runs `conda env create -f environment.yml` or `conda env update` |

**Error handling:**
- If install-deps.sh exits non-zero, capture stderr and report to user.
- Present the error and ask:

```
AskUserQuestion:
  question: "Dependency installation failed on {{SERVER_HOST}}. Error:\n{{stderr_last_20_lines}}\n\nWhat would you like to do?"
  candidates:
    - "Retry dependency installation"
    - "Skip this step and continue (dependencies may already be installed)"
    - "Connect me to the server for manual debugging"
    - "Abort deployment for this server"
```

If the user selects "Retry", re-run install-deps.sh. If "Skip", proceed to Step 3. If "Connect", display the SSH command for the user to run manually (`! ssh {{RUN_USER}}@{{SERVER_HOST}}`). If "Abort", skip to the next server or end.

#### Step 3: Project Build

Execute the build command(s) on the server. The build command was determined in Phase 2 (ProjectProfile) and rendered into `config.env`.

**Frontend build (if frontend detected):**

```bash
cd "{{PROJECT_DIR}}/{{FRONTEND_SUBDIRECTORY}}"
source "{{PROJECT_DIR}}/ops/config.env"
{{BUILD_COMMAND}}
```

The `BUILD_COMMAND` varies by framework:

| Framework | Build Command | Build Output Dir |
|---|---|---|
| Next.js | `npm run build` | `.next/` (SSR) or `out/` (static export) |
| Nuxt.js | `npm run build` | `.output/` |
| React (CRA) | `npm run build` | `build/` |
| React (Vite) | `npm run build` | `dist/` |
| Vue (Vite/CLI) | `npm run build` | `dist/` |
| Angular | `npm run build` | `dist/<name>/` |

**Backend build (if applicable):**

| Framework | Build Command |
|---|---|
| Flask / FastAPI | No build step (interpreted languages) |
| Django | `python manage.py collectstatic --noinput` |
| NestJS | `npm run build` (TypeScript → dist/) |
| Express (TypeScript) | `npm run build` if `build` script exists |

Use `ssh_exec_long` for build commands — they can take minutes for large projects.

**Error handling:** Same AskUserQuestion pattern as Step 2. Build failures are common (missing env vars, memory limits). Include the last 30 lines of build output in the error report.

#### Step 4: Stop Existing Services

Before installing new service units, stop and disable any existing services for this project. This is idempotent — it won't fail if services don't exist.

Execute via `ssh_exec`:

```bash
systemctl stop "{{PROJECT_NAME}}-watchdog.timer"     2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-watchdog.service"   2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-frontend.service"   2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-backend.service"    2>/dev/null || true
systemctl disable "{{PROJECT_NAME}}-watchdog.timer"     2>/dev/null || true
systemctl disable "{{PROJECT_NAME}}-frontend.service"   2>/dev/null || true
systemctl disable "{{PROJECT_NAME}}-backend.service"    2>/dev/null || true
```

**Order matters**: Stop watchdog first (so it doesn't restart services we're about to stop), then frontend, then backend.

Wait 2 seconds after stopping all services to allow ports to be released:

```bash
sleep 2
```

#### Step 5: Resolve Node.js Binary Path

If the project has any Node.js component (`HAS_NODE = true`), resolve the correct `node` binary path. This is critical because systemd services run under a limited PATH, and `sudo` resets PATH entirely.

Execute via `ssh_exec`:

```bash
# Resolution priority:
# 1. Explicit NODE_BIN from config.env
# 2. User's login shell (nvm/conda/fnm)
# 3. nvm directory scan (latest version first)
# 4. System PATH
# 5. Common fixed locations

resolve_node() {
    # 1. Explicit config
    if [ -n "$NODE_BIN" ] && [ -x "$NODE_BIN" ]; then
        echo "$NODE_BIN"
        return 0
    fi

    # 2. User's login shell
    local login_node
    login_node=$(su - "{{RUN_USER}}" -c 'which node 2>/dev/null' 2>/dev/null)
    if [ -n "$login_node" ] && [ -x "$login_node" ]; then
        echo "$login_node"
        return 0
    fi

    # 3. nvm directory scan
    local nvm_dir="${NVM_DIR:-/home/{{RUN_USER}}/.nvm}"
    if [ -d "$nvm_dir/versions/node" ]; then
        local latest
        latest=$(ls -v "$nvm_dir/versions/node/" 2>/dev/null | tail -1)
        if [ -n "$latest" ] && [ -x "$nvm_dir/versions/node/$latest/bin/node" ]; then
            echo "$nvm_dir/versions/node/$latest/bin/node"
            return 0
        fi
    fi

    # 4. System PATH
    local sys_node
    sys_node=$(which node 2>/dev/null)
    if [ -n "$sys_node" ]; then
        echo "$sys_node"
        return 0
    fi

    # 5. Common locations
    for loc in /usr/local/bin/node /usr/bin/node /snap/bin/node; do
        if [ -x "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done

    return 1
}

NODE_BIN=$(resolve_node)
if [ -z "$NODE_BIN" ]; then
    echo "ERROR: Could not find Node.js binary" >&2
    exit 1
fi
echo "Resolved NODE_BIN=$NODE_BIN (version: $($NODE_BIN --version))"
```

Also resolve PATH_DIRS — the full PATH from the user's login shell, used in systemd `Environment=PATH=...`:

```bash
PATH_DIRS=$(su - "{{RUN_USER}}" -c 'echo $PATH' 2>/dev/null || echo "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
echo "PATH_DIRS=$PATH_DIRS"
```

Record `NODE_BIN` and `PATH_DIRS` for use in template substitution.

#### Step 6: Install systemd Unit Files

Run the rendered `install.sh` on the server. This script performs template substitution on the systemd unit files and installs them to `/etc/systemd/system/`.

```bash
cd "{{PROJECT_DIR}}" && chmod +x ops/install.sh && sudo bash ops/install.sh --no-start
```

The `--no-start` flag tells install.sh to install units without starting them — we'll start them ourselves in a controlled sequence in Step 8.

**What install.sh does internally:**

1. Reads `ops/config.env` to get all variable values
2. Resolves Node.js binary and user PATH (Step 5 logic)
3. For each template in `ops/templates/`:
   - Applies `sed` substitution for all `{{VARIABLE}}` placeholders
   - Writes the rendered unit file to `/etc/systemd/system/{{PROJECT_NAME}}-*.service`
4. Installs watchdog service + timer (unless `--no-watchdog`)
5. Installs logrotate config (unless `--no-logrotate`)
6. Runs `systemctl daemon-reload`
7. Enables all installed units

**Conditional unit installation based on project type:**

| Project Type | Units Installed |
|---|---|
| fullstack | `backend.service` + `frontend.service` + `watchdog.*` |
| backend_only | `backend.service` + `watchdog.*` |
| frontend_only | `frontend.service` + `watchdog.*` |
| monolith | `frontend.service` (serves both frontend + API) + `watchdog.*` |

#### Step 7: systemd Reload and Enable

After install.sh completes, verify that the units are properly installed and enabled:

```bash
systemctl daemon-reload

# Enable units (they start on boot)
{{IF HAS_BACKEND}}
systemctl enable "{{PROJECT_NAME}}-backend.service"
{{ENDIF HAS_BACKEND}}

{{IF HAS_FRONTEND}}
systemctl enable "{{PROJECT_NAME}}-frontend.service"
{{ENDIF HAS_FRONTEND}}

systemctl enable "{{PROJECT_NAME}}-watchdog.timer"

# Verify unit files exist
ls -la /etc/systemd/system/{{PROJECT_NAME}}-*.service /etc/systemd/system/{{PROJECT_NAME}}-*.timer 2>/dev/null
```

If any unit file is missing, report the error and abort.

#### Step 8: Start Services (Sequenced)

Start services in dependency order with health waiting between each step. This ensures the backend is healthy before the frontend starts (important for fullstack projects where the frontend SSR may call the backend API during startup).

**Step 8a: Start backend (if detected)**

```bash
{{IF HAS_BACKEND}}
systemctl start "{{PROJECT_NAME}}-backend.service"

# Wait for backend to become healthy (up to 60 seconds)
for i in $(seq 1 60); do
    if curl -sf --max-time 5 "http://localhost:{{BACKEND_PORT}}/health" > /dev/null 2>&1; then
        echo "Backend healthy after ${i}s"
        break
    fi
    # Fallback: check if port is listening (process alive but health endpoint not ready)
    if [ $i -eq 30 ]; then
        if ss -tlnH "sport = :{{BACKEND_PORT}}" | grep -q "{{BACKEND_PORT}}"; then
            echo "Backend port {{BACKEND_PORT}} is listening (health endpoint not responding yet, continuing...)"
        fi
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: Backend did not become healthy within 60s"
        systemctl status "{{PROJECT_NAME}}-backend.service" --no-pager
        journalctl -u "{{PROJECT_NAME}}-backend.service" -n 20 --no-pager
    fi
    sleep 1
done
{{ENDIF HAS_BACKEND}}
```

**Step 8b: Start frontend (if detected)**

```bash
{{IF HAS_FRONTEND}}
systemctl start "{{PROJECT_NAME}}-frontend.service"

# Wait for frontend to become healthy (up to 60 seconds)
for i in $(seq 1 60); do
    if curl -sf --max-time 5 "http://localhost:{{FRONTEND_PORT}}/" > /dev/null 2>&1; then
        echo "Frontend healthy after ${i}s"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: Frontend did not become healthy within 60s"
        systemctl status "{{PROJECT_NAME}}-frontend.service" --no-pager
        journalctl -u "{{PROJECT_NAME}}-frontend.service" -n 20 --no-pager
    fi
    sleep 1
done
{{ENDIF HAS_FRONTEND}}
```

**Step 8c: Start watchdog timer**

```bash
systemctl start "{{PROJECT_NAME}}-watchdog.timer"
echo "Watchdog timer started (interval: {{WATCHDOG_INTERVAL}}s)"
```

#### Step 9: Quick Status Check

After all services are started, run a quick status check to confirm everything is running:

```bash
echo "=== Service Status ==="
systemctl is-active "{{PROJECT_NAME}}-backend.service" 2>/dev/null || echo "backend: not installed"
systemctl is-active "{{PROJECT_NAME}}-frontend.service" 2>/dev/null || echo "frontend: not installed"
systemctl is-active "{{PROJECT_NAME}}-watchdog.timer" 2>/dev/null || echo "watchdog: not installed"

echo ""
echo "=== Port Status ==="
ss -tlnH "sport = :{{BACKEND_PORT}}" 2>/dev/null
ss -tlnH "sport = :{{FRONTEND_PORT}}" 2>/dev/null
```

If any expected service is not active, this is a deployment failure — proceed to Phase 7 verification which will generate a proper failure report.

#### Step 10: Framework-Specific ExecStart Reference

The `ExecStart` directive in each service unit is critical and varies by framework. This step documents the exact commands used, for debugging reference:

**Backend ExecStart by framework:**

| Framework | ExecStart | Working Directory |
|---|---|---|
| Flask | `{{VENV_PYTHON}} app.py` | `{{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}` |
| Flask (gunicorn) | `{{VENV_PYTHON}} -m gunicorn -w 4 -b 0.0.0.0:{{BACKEND_PORT}} app:app` | `{{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}` |
| Django | `{{VENV_PYTHON}} manage.py runserver 0.0.0.0:{{BACKEND_PORT}}` | `{{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}` |
| Django (gunicorn) | `{{VENV_PYTHON}} -m gunicorn -w 4 -b 0.0.0.0:{{BACKEND_PORT}} {{DJANGO_WSGI_MODULE}}.wsgi:application` | `{{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}` |
| FastAPI | `{{VENV_PYTHON}} -m uvicorn main:app --host 0.0.0.0 --port {{BACKEND_PORT}} --workers 4` | `{{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}` |
| Express | `{{NODE_BIN}} server.js` | `{{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}` |
| NestJS | `{{NODE_BIN}} dist/main.js` | `{{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}` |
| Fastify / Koa | `{{NODE_BIN}} {{BACKEND_ENTRY_POINT}}` | `{{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}` |

**Frontend ExecStart by framework:**

| Framework | ExecStart | Working Directory |
|---|---|---|
| Next.js (standalone) | `{{NODE_BIN}} server.js` | `{{PROJECT_DIR}}/{{FRONTEND_SUBDIRECTORY}}` |
| Next.js (.next) | `{{NODE_BIN}} node_modules/.bin/next start -p {{FRONTEND_PORT}}` | `{{PROJECT_DIR}}/{{FRONTEND_SUBDIRECTORY}}` |
| Nuxt.js | `{{NODE_BIN}} .output/server/index.mjs` | `{{PROJECT_DIR}}/{{FRONTEND_SUBDIRECTORY}}` |
| React/Vue/Angular (static) | `{{NODE_BIN}} node_modules/.bin/serve {{BUILD_OUTPUT}} -l {{FRONTEND_PORT}}` | `{{PROJECT_DIR}}/{{FRONTEND_SUBDIRECTORY}}` |
| Static (no framework) | Served by Nginx directly — no frontend service needed | — |

**Note on static sites:** If the frontend produces static output (React, Vue, Angular in SPA mode) and Nginx is configured, there is no need for a frontend systemd service. Nginx serves the static files directly from the build output directory. In this case, skip frontend service installation entirely.

#### Step 11: Single-Service Project Handling

For `frontend_only` or `backend_only` projects, simplify the deployment:

**`backend_only` project:**
- Skip all frontend-related steps (no frontend build, no frontend service)
- Watchdog monitors only the backend service
- Health check targets only the backend health endpoint
- Service dependency chain: backend → watchdog (no frontend in between)

**`frontend_only` project:**
- Skip all backend-related steps
- Watchdog monitors only the frontend service
- If the frontend is a static site served by Nginx, skip the frontend service entirely — only configure Nginx

**`monolith` project (Next.js/Nuxt.js):**
- Deploy as a single frontend service (the framework handles both frontend and API)
- The "backend port" is the same as the "frontend port" (single process)
- Watchdog monitors the single service
- Health check targets the frontend URL

---

**Phase 6A output gate:** All expected systemd services must be in `active (running)` state. The watchdog timer must be `active (waiting)`. If any service failed to start, proceed to Phase 7 for verification and failure handling — do NOT attempt automatic fixes at this stage.
