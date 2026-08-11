# Spec 02: Template System

## Purpose

Define the template file format, variable resolution pipeline, and rendering engine that transforms `.tpl` template files into project-specific deployment scripts and configuration files.

## Template Format

### Placeholder Syntax

All templates use double-curly-brace placeholders: `{{VARIABLE_NAME}}`

This is consistent with the existing InkClaw ops scripts and widely recognized.

### Conditional Blocks

Templates support simple conditional sections:

```bash
# {{IF FEATURE_WATCHDOG}}
# ... watchdog-related content ...
# {{ENDIF FEATURE_WATCHDOG}}
```

And negation:

```bash
# {{IF_NOT FEATURE_DOCKER}}
# ... systemd-only content ...
# {{ENDIF_NOT FEATURE_DOCKER}}
```

### Iteration (for multi-service)

For projects with multiple services:

```bash
# {{FOR_EACH SERVICE}}
ExecStart={{SERVICE_ENTRY_POINT}}
# {{END_FOR_EACH}}
```

## Variable Registry

### Auto-Detected Variables (from ProjectProfile)

| Variable | Source | Example |
|----------|--------|---------|
| `PROJECT_NAME` | project_name | `my-webapp` |
| `PROJECT_DIR` | Absolute server path | `/home/deploy/my-webapp` |
| `RUN_USER` | SSH username or specified | `deploy` |
| `RUN_GROUP` | User's primary group | `deploy` |
| `FRONTEND_FRAMEWORK` | Detection result | `nextjs` |
| `BACKEND_FRAMEWORK` | Detection result | `flask` |
| `FRONTEND_PORT` | Default or user override | `3000` |
| `BACKEND_PORT` | Default or user override | `5000` |
| `NODE_BIN` | Resolved on server | `/home/deploy/.nvm/versions/node/v20/bin/node` |
| `VENV_PYTHON` | Resolved on server | `/home/deploy/my-webapp/backend/.venv/bin/python` |
| `BUILD_COMMAND` | From package.json | `npm run build` |
| `FRONTEND_START` | Framework-specific | `node server.js` |
| `BACKEND_START` | Framework-specific | `python app.py` |

### User-Provided Variables

| Variable | Prompt | Default |
|----------|--------|---------|
| `SERVER_HOST` | Server IP/hostname | — (required) |
| `SERVER_PORT` | SSH port | `22` |
| `SERVER_USER` | SSH username | — (required) |
| `NGINX_DOMAIN` | Domain name(s) | empty (skip Nginx) |
| `NGINX_SITE_NAME` | Nginx config filename | `PROJECT_NAME` |
| `WATCHDOG_INTERVAL` | Health check interval | `60` |
| `WATCHDOG_FAIL_THRESHOLD` | Failures before restart | `5` |
| `LOG_MAX_SIZE` | Log rotation size | `50M` |
| `LOG_ROTATE_COUNT` | Rotated files to keep | `7` |

### Computed Variables

| Variable | Computation |
|----------|------------|
| `PATH_DIRS` | Resolved on server: `dirname(NODE_BIN):dirname(VENV_PYTHON):$PATH` |
| `USER_DATA_DIR` | `/home/$RUN_USER/.$PROJECT_NAME-data` |
| `DEPLOY_TIMESTAMP` | ISO 8601 at deploy time |
| `BACKUP_DIR` | `$PROJECT_DIR/.deploy-backups/$DEPLOY_TIMESTAMP` |

## Rendering Pipeline

```
1. Load template file (.tpl)
2. Resolve conditional blocks (IF/ENDIF)
3. Resolve iteration blocks (FOR_EACH)
4. Substitute all {{VARIABLE}} placeholders
5. Validate: check for any remaining unresolved {{...}} placeholders
6. Write output file (without .tpl extension)
```

### Rendering Implementation

The rendering happens via the SKILL's instructions to Claude Code — Claude reads each template, substitutes variables using `sed` or inline Python, and writes the output. This is NOT a runtime rendering engine; it's part of the SKILL execution flow.

For SSH-deployed templates, the SKILL:
1. Renders locally first
2. Uploads rendered files via SFTP
3. Sets correct permissions (`chmod +x` for .sh files)

## Template Inventory

### ops/ Scripts (8 templates)

| Template | Output | Purpose |
|----------|--------|---------|
| `config.env.tpl` | `ops/config.env` | All configurable parameters |
| `install.sh.tpl` | `ops/install.sh` | systemd service registration |
| `install-deps.sh.tpl` | `ops/install-deps.sh` | Dependency installation |
| `uninstall.sh.tpl` | `ops/uninstall.sh` | Service removal |
| `status.sh.tpl` | `ops/status.sh` | Service status display |
| `logs.sh.tpl` | `ops/logs.sh` | Log viewer |
| `healthcheck.sh.tpl` | `ops/healthcheck.sh` | Watchdog health check |
| `deploy.sh.tpl` | `ops/deploy.sh` | One-command redeploy |

### systemd Templates (5 templates)

| Template | Output | Purpose |
|----------|--------|---------|
| `backend.service.tpl` | `ops/templates/{name}-backend.service` | Backend systemd unit |
| `frontend.service.tpl` | `ops/templates/{name}-frontend.service` | Frontend systemd unit |
| `watchdog.service.tpl` | `ops/templates/{name}-watchdog.service` | Health check oneshot |
| `watchdog.timer.tpl` | `ops/templates/{name}-watchdog.timer` | Timer trigger |
| `logrotate.tpl` | `ops/templates/{name}-logrotate` | Log rotation config |

### Nginx Templates (3 templates)

| Template | Output | Purpose |
|----------|--------|---------|
| `site-https.tpl` | `ops/templates/{name}-nginx` | HTTPS + SSL config |
| `site-http.tpl` | `ops/templates/{name}-nginx-http` | HTTP-only config |
| `site-stream.tpl` | (merged into above) | SSE/WebSocket settings |

### Docker Templates (4 templates)

| Template | Output | Purpose |
|----------|--------|---------|
| `Dockerfile.node.tpl` | `Dockerfile` | Node.js app container |
| `Dockerfile.python.tpl` | `Dockerfile` | Python app container |
| `Dockerfile.fullstack.tpl` | `Dockerfile` | Multi-stage fullstack |
| `docker-compose.tpl` | `docker-compose.yml` | Multi-service compose |

## Validation Rules

1. All required variables must be resolved before rendering
2. No `{{...}}` placeholders may remain in output files
3. Shell scripts must pass basic syntax check (`bash -n`)
4. systemd unit files must have valid `[Unit]`, `[Service]`, `[Install]` sections
5. Nginx configs must pass `nginx -t` after installation
