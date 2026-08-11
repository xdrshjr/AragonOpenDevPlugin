# Spec 04: systemd Deployment Pipeline

## Purpose

Define the complete systemd-based deployment pipeline: dependency installation, project building, systemd service registration, watchdog setup, logrotate configuration, and service lifecycle management.

## Prerequisites

- Server has systemd (checked in pre-flight)
- Server has Python 3.8+ and/or Node.js 18+ (depending on project type)
- SSH connection established
- ProjectProfile and rendered templates available

## Deployment Steps

### Step 1: Dependency Installation

Execute the rendered `install-deps.sh` on the server:

```bash
# Upload and execute
chmod +x ops/install-deps.sh
sudo ./ops/install-deps.sh
```

The `install-deps.sh` template handles:

**For Python backends:**
- Create/activate virtualenv if not exists
- `pip install -r requirements.txt`
- Detect conda environment and adapt

**For Node.js projects:**
- `npm install` (or yarn/pnpm based on lockfile detection)
- `npm rebuild` for native modules
- Install Playwright if needed (detected from dependencies)

**System dependencies (if sudo available):**
- VNC packages (xvfb, x11vnc) if needed
- Other system libs from a `system-deps.txt` if present

### Step 2: Project Build

Execute build commands on the server:

**Frontend builds:**
| Framework | Build Command | Output Dir |
|-----------|--------------|-----------|
| Next.js | `npm run build` | `out/` or `.next/` |
| React (CRA) | `npm run build` | `build/` |
| Vue (Vite) | `npm run build` | `dist/` |
| Angular | `ng build` | `dist/` |

**Backend builds:**
- Flask/FastAPI: No build step (interpreted)
- Django: `python manage.py collectstatic --noinput`

### Step 3: Stop Existing Services

```bash
systemctl stop {{PROJECT_NAME}}-watchdog.timer   2>/dev/null || true
systemctl stop {{PROJECT_NAME}}-watchdog.service 2>/dev/null || true
systemctl stop {{PROJECT_NAME}}-frontend.service 2>/dev/null || true
systemctl stop {{PROJECT_NAME}}-backend.service  2>/dev/null || true
systemctl disable {{PROJECT_NAME}}-watchdog.timer   2>/dev/null || true
systemctl disable {{PROJECT_NAME}}-frontend.service 2>/dev/null || true
systemctl disable {{PROJECT_NAME}}-backend.service  2>/dev/null || true
```

### Step 4: Install systemd Unit Files

Use the template substitution pattern from existing `install.sh`:

```bash
install_template() {
    local src="$1" dest="$2"
    sed \
        -e "s|{{PROJECT_DIR}}|${PROJECT_DIR}|g" \
        -e "s|{{RUN_USER}}|${RUN_USER}|g" \
        -e "s|{{RUN_GROUP}}|${RUN_GROUP}|g" \
        ... (all variables)
        "$src" > "$dest"
}
```

Files installed to `/etc/systemd/system/`:
- `{{PROJECT_NAME}}-backend.service` (if backend detected)
- `{{PROJECT_NAME}}-frontend.service` (if frontend detected)
- `{{PROJECT_NAME}}-watchdog.service`
- `{{PROJECT_NAME}}-watchdog.timer`

### Step 5: Install Watchdog

Health check script (`healthcheck.sh`) checks:
- HTTP health endpoint for each service (configurable per-service)
- Port listening state (fallback when HTTP check fails but process is alive)
- Consecutive failure counting with configurable threshold
- Auto-restart via `systemctl restart` after threshold

### Step 6: Install Logrotate

Rendered logrotate config installed to `/etc/logrotate.d/{{PROJECT_NAME}}`.

### Step 7: Reload systemd & Enable Services

```bash
systemctl daemon-reload
systemctl enable {{PROJECT_NAME}}-backend.service
systemctl enable {{PROJECT_NAME}}-frontend.service
systemctl enable {{PROJECT_NAME}}-watchdog.timer
```

### Step 8: Start Services

Sequential start with health waiting:

1. Start backend → wait up to 30s for health endpoint
2. Start frontend → wait up to 30s for health endpoint
3. Start watchdog timer

### Step 9: Verify

Check all services are active and healthy (delegates to Spec 07).

## Service Templates

### Backend Service Template

Adapts based on backend type:

| Backend | ExecStart | WorkingDirectory |
|---------|-----------|-----------------|
| Flask | `{{VENV_PYTHON}} app.py` | `{{PROJECT_DIR}}/backend` |
| Django | `{{VENV_PYTHON}} manage.py runserver 0.0.0.0:{{BACKEND_PORT}}` | `{{PROJECT_DIR}}` |
| FastAPI | `{{VENV_PYTHON}} -m uvicorn main:app --port {{BACKEND_PORT}}` | `{{PROJECT_DIR}}` |
| Express | `{{NODE_BIN}} server.js` | `{{PROJECT_DIR}}` |

### Frontend Service Template

| Frontend | ExecStart | WorkingDirectory |
|----------|-----------|-----------------|
| Next.js (standalone) | `{{NODE_BIN}} server.js` | `{{PROJECT_DIR}}` |
| Next.js (static export) | `{{NODE_BIN}} node_modules/.bin/serve out -p {{FRONTEND_PORT}}` | `{{PROJECT_DIR}}` |
| React/Vue (static) | `{{NODE_BIN}} node_modules/.bin/serve dist -p {{FRONTEND_PORT}}` | `{{PROJECT_DIR}}` |

### Common Service Properties

All service units include:
- `Restart=on-failure` with `RestartSec=5s`
- `StartLimitBurst=5` / `StartLimitIntervalSec=300`
- Security hardening: `NoNewPrivileges=true`, `ProtectSystem=full`
- Journal logging: `StandardOutput=journal`, `SyslogIdentifier={{PROJECT_NAME}}-*`
- `ReadWritePaths` for project and user data directories

## Node.js Resolution

The `resolve_node()` function from the existing install.sh is generalized:

1. Explicit `NODE_BIN` from config.env
2. User's interactive login shell (nvm/conda)
3. nvm directories scan (latest version first)
4. System PATH
5. Common locations: `/usr/local/bin/node`, `/usr/bin/node`, `/snap/bin/node`

This is critical when running under `sudo` since PATH is reset.

## Single-Service Projects

For `frontend_only` or `backend_only` project types:
- Only generate the relevant service unit file
- Skip the dependency between frontend and backend
- Watchdog monitors only the single service
- Health check targets only the single service endpoint
