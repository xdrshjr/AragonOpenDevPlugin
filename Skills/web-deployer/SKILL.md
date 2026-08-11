---
name: web-deployer
description: Deploy any web project to Linux servers with auto-detection, systemd/Docker service management, Nginx reverse proxy, and independent ops toolkit generation. Supports interactive guided mode and full-auto mode with multi-server batch deployment. Use when the user mentions "deploy", "部署", "server setup", "服务器部署", "systemd", "web deploy", "ops scripts", "运维脚本", or invokes /web-deployer.
---

# Web Deployer

Deploy any web project (frontend, backend, or fullstack) to one or more Linux servers. Auto-detect project type, render deployment templates, execute via SSH, verify with health checks, and leave behind an independent `ops/` toolkit.

## Overview

```
Phase 1: Initialization → Language + Mode selection
Phase 2: Project Analysis → Auto-detect project type, frameworks, ports
Phase 3: Server Info Collection → SSH connection details, pre-flight checks
Phase 4: Deployment Configuration → Variable resolution, Nginx/SSL decisions
Phase 5: Template Rendering → Generate ops/ toolkit (scripts + configs)
Phase 6: Remote Deployment → Execute systemd or Docker pipeline + Nginx
Phase 7: Post-Deploy Verification → Health checks, failure handling, rollback
Phase 8: Summary & Handoff → Report, quick commands, memory save
```

## Supported Project Types

| Type | Examples |
|------|---------|
| Fullstack (separated) | React + Flask, Vue + Django, Next.js + Express |
| Monolith | Next.js (with API routes), Nuxt.js, Django fullstack |
| Frontend only | React SPA, Vue SPA, Angular, static sites |
| Backend only | Flask API, FastAPI, Express, Django REST |

## SSH Helper Infrastructure

All remote operations use Python `paramiko` via the `Bash` tool. These helper functions are called inline throughout the deployment phases.

### Prerequisites

```python
try:
    import paramiko
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "paramiko"])
    import paramiko
import os, stat, json, time
```

### ssh_connect

```python
def ssh_connect(host, username, password=None, key_path=None, port=22, timeout=15):
    """
    Establish SSH connection. Auth priority: key_path > password > SSH agent.
    Returns paramiko.SSHClient.
    """
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    kwargs = dict(hostname=host, port=port, username=username, timeout=timeout)
    if key_path:
        expanded = os.path.expanduser(key_path)
        if not os.path.isfile(expanded):
            raise FileNotFoundError(f"SSH key not found: {expanded}")
        kwargs["key_filename"] = expanded
    elif password:
        kwargs["password"] = password
    ssh.connect(**kwargs)
    return ssh
```

### ssh_exec

```python
def ssh_exec(ssh, commands, timeout=120):
    """Execute one or more commands. Returns list[dict] with cmd, stdout, stderr, exit_code."""
    if isinstance(commands, str):
        commands = [commands]
    results = []
    for cmd in commands:
        stdin, stdout, stderr = ssh.exec_command(cmd)
        stdout.channel.settimeout(timeout)
        try:
            out = stdout.read().decode("utf-8", errors="replace")
            err = stderr.read().decode("utf-8", errors="replace")
        except Exception as e:
            out = ""
            err = f"Read timeout or channel error: {e}"
        exit_code = stdout.channel.recv_exit_status()
        results.append({"cmd": cmd, "stdout": out.strip(), "stderr": err.strip(), "exit_code": exit_code})
    return results
```

### ssh_exec_long

```python
def ssh_exec_long(ssh, command, timeout=600):
    """Execute long-running command with streaming output. Returns single result dict."""
    stdin, stdout, stderr = ssh.exec_command(command)
    stdout.channel.settimeout(timeout)
    lines = []
    try:
        for line in iter(stdout.readline, ""):
            lines.append(line.rstrip())
    except Exception:
        pass
    err_lines = []
    try:
        err_lines = stderr.read().decode("utf-8", errors="replace").strip().split("\n")
    except Exception:
        pass
    exit_code = stdout.channel.recv_exit_status()
    return {
        "cmd": command,
        "stdout": "\n".join(lines),
        "stderr": "\n".join(err_lines),
        "exit_code": exit_code,
    }
```

### sftp_makedirs

```python
def sftp_makedirs(sftp, remote_dir):
    """Recursively create remote directories."""
    dirs_to_create = []
    current = remote_dir
    while current and current != "/":
        try:
            sftp.stat(current)
            break
        except (IOError, OSError):
            dirs_to_create.append(current)
            current = current.rsplit("/", 1)[0] if "/" in current else ""
    for d in reversed(dirs_to_create):
        sftp.mkdir(d)
```

### sftp_upload

```python
def sftp_upload(ssh, local_path, remote_path, exclude=None):
    """
    Upload file or directory recursively to remote server.
    exclude: list of patterns to skip (e.g., ["node_modules/", ".git/", ".venv/"])
    """
    sftp = ssh.open_sftp()
    exclude = exclude or []

    def should_exclude(path):
        for pattern in exclude:
            if pattern in path:
                return True
        return False

    try:
        if os.path.isfile(local_path):
            remote_dir = remote_path.rsplit("/", 1)[0]
            sftp_makedirs(sftp, remote_dir)
            sftp.put(local_path, remote_path)
        elif os.path.isdir(local_path):
            sftp_makedirs(sftp, remote_path)
            for root, dirs, files in os.walk(local_path):
                # Filter excluded directories
                dirs[:] = [d for d in dirs if not should_exclude(d + "/")]
                rel = os.path.relpath(root, local_path).replace("\\", "/")
                remote_root = f"{remote_path}/{rel}" if rel != "." else remote_path
                sftp_makedirs(sftp, remote_root)
                for f in files:
                    if should_exclude(f):
                        continue
                    local_file = os.path.join(root, f)
                    remote_file = f"{remote_root}/{f}"
                    sftp.put(local_file, remote_file)
    finally:
        sftp.close()
```

### ensure_connected

```python
def ensure_connected(ssh, host, username, password=None, key_path=None, port=22):
    """Reconnect SSH if the connection was lost (e.g., after a long operation)."""
    try:
        ssh.exec_command("echo ok", timeout=5)
        return ssh
    except Exception:
        ssh.close()
        return ssh_connect(host, username, password, key_path, port)
```

---

## Phase 1: Initialization

### Step 1.1: Language Selection

```
AskUserQuestion:
  question: "Which language would you like for this deployment session?\n请选择部署会话的语言："
  candidates:
    - "English"
    - "中文 (Chinese)"
```

Store the language choice. All subsequent interaction, generated README, and script comments follow this choice.

### Step 1.2: Deployment Mode

```
AskUserQuestion:
  question: "Select deployment mode:"
  candidates:
    - "Interactive guided mode (recommended for first deploy) — step-by-step with confirmations"
    - "Full-auto mode (for known environments) — minimal interaction, use defaults"
    - "Generate ops scripts only (no deployment) — create templates without executing"
```

Store the mode. In **guided mode**, every phase presents confirmations. In **auto mode**, use detected defaults and env vars with minimal prompts. In **scripts-only mode**, stop after Phase 5.

---

## Phase 2: Project Analysis

Scan the current working directory to auto-detect project type, technology stack, structure, and deployment requirements. Produce a `ProjectProfile` consumed by all downstream phases.

### Step 2.1: Marker File Discovery

Use `Glob` to scan the project root for detection markers. Run all glob patterns in parallel:

```
Glob: package.json
Glob: requirements.txt / Pipfile / pyproject.toml
Glob: next.config.* / nuxt.config.* / vue.config.* / vite.config.* / angular.json
Glob: app.py / wsgi.py / manage.py / main.py
Glob: server.js / server.ts / index.js / index.ts
Glob: Dockerfile / docker-compose.yml / docker-compose.yaml / compose.yml / compose.yaml
Glob: ops/config.env
Glob: environment.yml / environment.yaml
Glob: backend/ / frontend/ / */package.json
```

### Step 2.2: Detection Marker Table

| Marker File | Signal | Category |
|---|---|---|
| `package.json` | Node.js project | runtime |
| `requirements.txt` / `Pipfile` / `pyproject.toml` | Python project | runtime |
| `next.config.*` | Next.js | frontend_framework |
| `nuxt.config.*` | Nuxt.js | frontend_framework |
| `vue.config.js` OR `vite.config.*` with Vue dep | Vue | frontend_framework |
| `angular.json` | Angular | frontend_framework |
| `app.py` / `wsgi.py` | Flask backend | backend_framework |
| `manage.py` | Django backend | backend_framework |
| `main.py` with FastAPI import | FastAPI backend | backend_framework |
| `server.js` / `server.ts` with express import | Express backend | backend_framework |
| `Dockerfile` | Docker-ready | docker |
| `docker-compose.*` / `compose.*` | Docker Compose ready | docker |
| `ops/config.env` | Existing ops toolkit | ops |
| `environment.yml` | Conda environment | runtime |
| `backend/` / `frontend/` | Separated structure | structure |

### Step 2.3: Parse package.json

If `package.json` exists, read it and extract: `name`, `scripts.build`, `scripts.start`, framework dependencies (`next`, `react`, `vue`, `@angular/core`, `express`, `fastify`, `koa`), package manager (detect from `yarn.lock` / `pnpm-lock.yaml` / default `npm`).

### Step 2.4: Backend Detection

Check `backend/` subdirectory first, then root. Ordered detection:

1. **Flask**: `app.py`/`wsgi.py` + flask in requirements → entry: `app.py`, port: 5000
2. **Django**: `manage.py` + django in requirements → entry: `manage.py`, port: 8000
3. **FastAPI**: `main.py` + fastapi/uvicorn in requirements → entry: `uvicorn main:app`, port: 8000
4. **Express**: `server.js`/`server.ts` + express in package.json → entry: `server.js`, port: 3001
5. **NestJS**: `@nestjs/core` in package.json → entry: `dist/main.js`, port: 3001

For Python backends, detect virtualenv: `.venv/`, `venv/`, or conda (`environment.yml`).

### Step 2.5: Frontend Detection

Check `frontend/` subdirectory first, then root. Ordered detection:

1. **Next.js**: `next.config.*` or `next` in deps → build: `npm run build`, output: `.next/`, port: 3000
2. **Nuxt.js**: `nuxt.config.*` or `nuxt` in deps → build: `npm run build`, output: `.output/`, port: 3000
3. **Vue**: `vue` in deps + vite/vue config → build: `npm run build`, output: `dist/`, port: 3000
4. **React**: `react` in deps (not Next.js) → build: `npm run build`, output: `build/` or `dist/`, port: 3000
5. **Angular**: `angular.json` or `@angular/core` → build: `npm run build`, output: `dist/<name>/`, port: 3000

### Step 2.6: Docker Detection

Check for `Dockerfile` and `docker-compose.yml`/`compose.yml`. If found, read to extract base image, exposed ports, and services.

### Step 2.7: Project Type Classification

```
if frontend.detected AND backend.detected:
    project_type = "fullstack"
elif frontend.detected AND framework in ["nextjs", "nuxtjs"] AND has API routes:
    project_type = "monolith"
elif frontend.detected:
    project_type = "frontend_only"
elif backend.detected:
    project_type = "backend_only"
else:
    project_type = "unknown"  # ask user
```

### Step 2.8: Assemble & Present ProjectProfile

```
ProjectProfile:
  project_name: string          # kebab-case, from package.json name or directory name
  project_dir: string           # absolute path
  project_type: string          # fullstack | frontend_only | backend_only | monolith | unknown
  frontend:
    detected, framework, entry_point, build_command, build_output, port, package_manager, subdirectory
  backend:
    detected, framework, entry_point, production_command, runtime, venv_path, requirements_file, port, subdirectory
  docker:
    has_dockerfile, has_compose, dockerfile_path, compose_path
  deployment:
    has_ops, has_existing_services, recommended_mode
```

Present to user via `AskUserQuestion`:

```
AskUserQuestion:
  question: |
    I've analyzed your project. Here's what I detected:
    [... formatted ProjectProfile ...]

    Is this correct?
  candidates:
    - "Looks correct — proceed"
    - "I need to correct some values"
    - "This is wrong — let me describe my project manually"
```

In auto mode, show the summary and proceed unless detection returned `"unknown"`.

**Edge cases:**
- Monorepo: ask user which package to deploy
- No markers: fall back to manual description
- Conflicting frameworks: ask user to disambiguate
- Existing ops/: read config.env for higher-priority defaults
- Port conflict (frontend == backend): warn and auto-fix

### Step 2.9: Deployment Type Selection

```
AskUserQuestion:
  question: "Select deployment type:"
  candidates:
    - "systemd (bare metal)"
    - "Docker"
    - "Both (generate configs for both)"
    - "Let the skill decide based on detection"
```

If "Let the skill decide": use Docker if Dockerfile/compose found, systemd otherwise.

---

## Phase 3: Server Info Collection

Collect SSH connection details for one or more target servers and run pre-flight checks.

### Step 3.1: Server Info Source

In auto mode, check these sources in order:
1. Environment variables: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_KEY`, `DEPLOY_PORT`, `DEPLOY_DIR`
2. Config file: `deploy-servers.json` in project root
3. Saved memory: check if server config was previously saved

If no auto-source found, or in guided mode, proceed to interactive collection.

### Step 3.2: Interactive Server Info Collection

```
AskUserQuestion:
  question: "Enter server connection details:"
  candidates:
    - "Host: (IP or hostname)"
    - "SSH Port: (default: 22)"
    - "Username: (e.g., deploy, root)"
    - "Auth: SSH key path OR password (key recommended)"
    - "Remote directory: (e.g., /home/deploy/my-project)"
```

Collect each field. For auth, prefer SSH key. Never store passwords — use `SSH_PASS` env var or interactive prompt.

### Step 3.3: Pre-Flight Checks

After collecting server info, establish SSH connection and run pre-flight checks:

```python
ssh = ssh_connect(host, username, password, key_path, port)
checks = ssh_exec(ssh, [
    "echo 'CONN_OK'",                                          # Connectivity
    "python3 --version 2>/dev/null || echo 'NO_PYTHON'",       # Python
    "node --version 2>/dev/null || echo 'NO_NODE'",            # Node.js
    "docker --version 2>/dev/null || echo 'NO_DOCKER'",        # Docker
    "nginx -v 2>&1 || echo 'NO_NGINX'",                        # Nginx
    "systemctl --version 2>/dev/null || echo 'NO_SYSTEMD'",    # systemd
    "git --version 2>/dev/null || echo 'NO_GIT'",              # Git
    "df -h / | tail -1",                                        # Disk
    "free -h | head -2",                                        # Memory
    f"ls /etc/letsencrypt/live/ 2>/dev/null || echo 'NO_LE'",  # Let's Encrypt
    f"systemctl list-units '{project_name}-*' --no-pager 2>/dev/null || echo 'NO_SERVICES'",  # Existing services
])
```

Present pre-flight report:

```
╔═══════════════════════════════════════════╗
║  Pre-Flight Check: {{SERVER_HOST}}         ║
╠═══════════════════════════════════════════╣
║  [✓] SSH connectivity: OK                  ║
║  [✓] Python: 3.11.5                        ║
║  [✓] Node.js: v20.10.0                     ║
║  [✓] Docker: 24.0.7                        ║
║  [✓] Nginx: 1.24.0                         ║
║  [✓] systemd: 252                          ║
║  [✓] Git: 2.43.0                           ║
║  [✓] Disk: 45G free (45%)                  ║
║  [✓] Memory: 3.2G available                ║
║  [!] SSL: No Let's Encrypt certs           ║
║  [–] Existing services: none               ║
╚═══════════════════════════════════════════╝
```

If critical checks fail (no Python for Python project, no Node for Node project, no Docker when Docker mode selected), warn the user and offer alternatives.

### Step 3.4: Multi-Server Collection

```
AskUserQuestion:
  question: "Would you like to deploy to additional servers?"
  candidates:
    - "Yes, add another server"
    - "No, deploy to this server only"
```

If yes, loop back to Step 3.2. Build a `server_contexts` dictionary with per-server info.

### Step 3.5: Build Server Context

For each server, store:

```python
server_context = {
    "host": host,
    "port": ssh_port,
    "username": username,
    "auth": {"key_path": key_path} or {"password": password},
    "remote_dir": remote_dir,
    "ssh": ssh_client,  # connected
    "preflight": preflight_results,
    "overrides": {},  # per-server variable overrides (NGINX_DOMAIN, ports, etc.)
}
```

---

## Phase 4: Deployment Configuration

Resolve all template variables and finalize deployment decisions.

### Step 4.1: Variable Resolution

Merge variables from multiple sources with this priority (highest first):

1. **User overrides** — explicit values provided by the user
2. **Auto-detected** — from ProjectProfile (Phase 2)
3. **Server-resolved** — from pre-flight checks (Node.js path, Python path)
4. **Defaults** — sensible fallbacks

Key variables:

| Variable | Source | Default |
|---|---|---|
| `PROJECT_NAME` | package.json name or dir name | required |
| `PROJECT_DIR` | remote_dir from server context | required |
| `RUN_USER` | SSH username | required |
| `RUN_GROUP` | same as RUN_USER | required |
| `BACKEND_PORT` | framework default | 5000 |
| `FRONTEND_PORT` | framework default | 3000 |
| `NODE_BIN` | resolved on server | auto |
| `VENV_PYTHON` | detected venv path | auto |
| `BACKEND_START` | framework production command | auto |
| `FRONTEND_START` | framework start command | auto |
| `BUILD_COMMAND` | package.json scripts.build | `npm run build` |
| `NGINX_DOMAIN` | user-provided | empty (skip Nginx) |
| `WATCHDOG_INTERVAL` | default | 60 |
| `WATCHDOG_FAIL_THRESHOLD` | default | 5 |
| `LOG_DIR` | default | logs |
| `LOG_MAX_SIZE` | default | 50M |
| `LOG_ROTATE_COUNT` | default | 7 |
| `DEPLOY_MODE` | user choice | systemd |

### Step 4.2: Nginx Decision

```
AskUserQuestion:
  question: "Nginx reverse proxy configuration:"
  candidates:
    - "Configure Nginx reverse proxy — enter domain name"
    - "Skip Nginx (I'll configure it myself)"
    - "Skip Nginx (no reverse proxy needed)"
```

If configuring Nginx, ask for domain:

```
AskUserQuestion:
  question: "Enter domain name(s) for Nginx (space-separated for multiple):"
  candidates:
    - "example.com"
    - "example.com www.example.com"
```

### Step 4.3: SSL Decision (If Nginx Selected)

```
AskUserQuestion:
  question: "SSL configuration:"
  candidates:
    - "Auto-detect SSL certificates on server"
    - "HTTP only (no SSL)"
    - "I'll set up SSL later with certbot"
```

### Step 4.4: Configuration Confirmation (Guided Mode)

In guided mode, present all resolved variables for confirmation:

```
AskUserQuestion:
  question: |
    Deployment configuration:

    Project:    {{PROJECT_NAME}}
    Type:       {{PROJECT_TYPE}}
    Deploy:     {{DEPLOY_MODE}}
    Backend:    {{BACKEND_FRAMEWORK}} on port {{BACKEND_PORT}}
    Frontend:   {{FRONTEND_FRAMEWORK}} on port {{FRONTEND_PORT}}
    Nginx:      {{NGINX_DOMAIN}} ({{SSL_STATUS}})
    Server(s):  {{SERVER_LIST}}

    Proceed with these settings?
  candidates:
    - "Yes, proceed"
    - "I need to change some values"
```

---

## Phase 5: Template Rendering & Ops Generation

Generate the complete `ops/` toolkit locally and prepare for upload.

### Step 5.1: Determine File Manifest

**Always generated:**
- `ops/config.env` — centralized configuration, sourced by all scripts
- `ops/deploy.sh` — one-command redeploy (git pull → deps → build → restart)
- `ops/install.sh` — register systemd services, watchdog, logrotate, Nginx
- `ops/install-deps.sh` — install Python/Node.js dependencies
- `ops/uninstall.sh` — remove all services and configs
- `ops/status.sh` — display service status, ports, health checks
- `ops/logs.sh` — view journalctl logs per service
- `ops/healthcheck.sh` — watchdog health check with failure counter
- `ops/README.md` — usage documentation (language-aware)

**systemd mode additional:**
- `ops/templates/{{PROJECT_NAME}}-backend.service` (if backend detected)
- `ops/templates/{{PROJECT_NAME}}-frontend.service` (if frontend detected)
- `ops/templates/{{PROJECT_NAME}}-watchdog.service`
- `ops/templates/{{PROJECT_NAME}}-watchdog.timer`
- `ops/templates/{{PROJECT_NAME}}-logrotate`
- `ops/templates/{{PROJECT_NAME}}-nginx` or `{{PROJECT_NAME}}-nginx-http`

**Docker mode additional:**
- `ops/docker-deploy.sh`, `ops/docker-status.sh`, `ops/docker-logs.sh`, `ops/docker-stop.sh`
- `Dockerfile` (if not existing)
- `docker-compose.yml` (if not existing)
- `.dockerignore` (if not existing)

### Step 5.2: Template Rendering Engine

Templates use `{{VARIABLE}}` placeholder syntax with conditional blocks:

```
{{IF CONDITION}}
  ... content included when CONDITION is true ...
{{ENDIF CONDITION}}

{{IF_NOT CONDITION}}
  ... content included when CONDITION is false ...
{{ENDIF_NOT CONDITION}}
```

**Rendering process (two-pass):**
1. **Pass 1 — Conditional resolution:** Evaluate all `{{IF}}`/`{{ENDIF}}` blocks. Include or remove content based on boolean flags (`HAS_BACKEND`, `HAS_FRONTEND`, `HAS_NODE`, `HAS_PYTHON`, `HAS_SSL`, `FRAMEWORK_*`, `PM_*`).
2. **Pass 2 — Variable substitution:** Replace all remaining `{{VARIABLE}}` placeholders with resolved values.

**Post-render validation:**
- No unresolved `{{...}}` placeholders remain
- Shell scripts pass `bash -n` syntax check
- Service files have required `[Unit]`, `[Service]`, `[Install]` sections

### Step 5.3: Read Templates and Render

For each template file in the skill's `templates/` directory:
1. Read the `.tpl` file from the skill directory
2. Apply the two-pass rendering with resolved variables
3. Write the rendered file to the project's `ops/` directory

Use the `Read` tool to read each template, then `Write` to create the rendered output.

### Step 5.4: Generate ops/README.md

Generate usage documentation in the selected language. Include:
- Prerequisites
- Quick start commands
- File descriptions
- Configuration guide
- Common operations (status, logs, deploy, uninstall)

### Step 5.5: Confirmation Before Upload (Guided Mode)

```
AskUserQuestion:
  question: |
    Generated files:
    {{FILE_LIST}}

    Ready to upload to server(s)?
  candidates:
    - "Yes, upload and deploy"
    - "Let me review the files first"
    - "Regenerate with different settings"
```

If "scripts-only" mode was selected in Phase 1, stop here.

### Step 5.6: Upload to Server(s)

For each target server:
1. Upload the entire `ops/` directory via SFTP
2. Set executable permissions on all `.sh` files
3. For Docker mode: also upload project source (excluding `node_modules/`, `.venv/`, `.git/`)

```python
for server in server_contexts:
    ssh = server["ssh"]
    sftp_upload(ssh, local_ops_dir, f"{server['remote_dir']}/ops/")
    ssh_exec(ssh, f"chmod +x {server['remote_dir']}/ops/*.sh")
```

---

## Phase 6: Remote Deployment Execution

Execute the deployment pipeline on each target server. The pipeline depends on the deployment mode.

### Multi-Server Orchestration

For multiple servers:
- **First deploy**: Execute sequentially (server by server) for easier debugging
- **Redeploy**: Can execute in parallel via Agent tool

```python
for server in server_contexts:
    ssh = ensure_connected(server["ssh"], ...)
    if deploy_mode == "systemd":
        execute_systemd_pipeline(ssh, server)  # Phase 6A
    elif deploy_mode == "docker":
        execute_docker_pipeline(ssh, server)    # Phase 6B
    if nginx_enabled:
        configure_nginx(ssh, server)            # Phase 6C
```

### Phase 6A: systemd Deployment

#### 6A.1: Pre-Deployment Backup

```bash
BACKUP_DIR="{{PROJECT_DIR}}/.deploy-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r "{{PROJECT_DIR}}/ops/config.env" "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/systemd/system/{{PROJECT_NAME}}-*.service "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/systemd/system/{{PROJECT_NAME}}-*.timer "$BACKUP_DIR/" 2>/dev/null || true
cp "/etc/nginx/sites-available/{{NGINX_SITE_NAME}}" "$BACKUP_DIR/" 2>/dev/null || true
systemctl list-units '{{PROJECT_NAME}}-*' --no-pager > "$BACKUP_DIR/service-state.txt" 2>/dev/null || true
echo "$(date -Iseconds)" > "$BACKUP_DIR/backup.timestamp"
ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true
```

#### 6A.2: Install Dependencies

Execute `install-deps.sh` via `ssh_exec_long`:

```bash
cd "{{PROJECT_DIR}}" && chmod +x ops/install-deps.sh && bash ops/install-deps.sh
```

On failure, ask user: Retry / Skip / Manual debug / Abort.

#### 6A.3: Build Project

Execute framework-specific build commands via `ssh_exec_long`:

- Frontend: `cd {{FRONTEND_SUBDIRECTORY}} && {{BUILD_COMMAND}}`
- Backend (Django): `python manage.py collectstatic --noinput`
- Backend (others): no build step needed

On failure, report last 30 lines and ask user.

#### 6A.4: Stop Existing Services

```bash
systemctl stop "{{PROJECT_NAME}}-watchdog.timer"     2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-watchdog.service"   2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-frontend.service"   2>/dev/null || true
systemctl stop "{{PROJECT_NAME}}-backend.service"    2>/dev/null || true
systemctl disable "{{PROJECT_NAME}}-watchdog.timer"     2>/dev/null || true
systemctl disable "{{PROJECT_NAME}}-frontend.service"   2>/dev/null || true
systemctl disable "{{PROJECT_NAME}}-backend.service"    2>/dev/null || true
sleep 2
```

#### 6A.5: Install systemd Units

```bash
cd "{{PROJECT_DIR}}" && chmod +x ops/install.sh && sudo bash ops/install.sh --no-start
```

This renders and installs unit files to `/etc/systemd/system/`, sets up watchdog and logrotate.

#### 6A.6: Start Services (Sequenced)

Start in dependency order with health waiting:

1. **Backend** → wait up to 60s for `curl -sf http://localhost:{{BACKEND_PORT}}/health`
2. **Frontend** → wait up to 60s for `curl -sf http://localhost:{{FRONTEND_PORT}}/`
3. **Watchdog timer** → start immediately

```bash
# Start backend
systemctl start "{{PROJECT_NAME}}-backend.service"
for i in $(seq 1 60); do
    curl -sf --max-time 5 "http://localhost:{{BACKEND_PORT}}/health" > /dev/null 2>&1 && break
    sleep 1
done

# Start frontend
systemctl start "{{PROJECT_NAME}}-frontend.service"
for i in $(seq 1 60); do
    curl -sf --max-time 5 "http://localhost:{{FRONTEND_PORT}}/" > /dev/null 2>&1 && break
    sleep 1
done

# Start watchdog
systemctl start "{{PROJECT_NAME}}-watchdog.timer"
```

**Single-service projects:**
- `backend_only`: skip frontend start, watchdog monitors backend only
- `frontend_only`: skip backend start, watchdog monitors frontend only
- `monolith`: deploy as single frontend service

### Phase 6B: Docker Deployment

#### 6B.1: Smart Detection

```bash
HAS_DOCKERFILE=false; HAS_COMPOSE=false
[ -f Dockerfile ] && HAS_DOCKERFILE=true
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -f "$f" ] && HAS_COMPOSE=true && break
done
```

Modes: `use_existing` | `use_dockerfile_generate_compose` | `use_compose` | `generate_all`

#### 6B.2: Pre-Deployment Backup

```bash
BACKUP_DIR="{{PROJECT_DIR}}/.deploy-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
docker compose ps --format json > "$BACKUP_DIR/container-state.json" 2>/dev/null || true
cp docker-compose.yml Dockerfile* .dockerignore "$BACKUP_DIR/" 2>/dev/null || true
cp "/etc/nginx/sites-available/{{NGINX_SITE_NAME}}" "$BACKUP_DIR/" 2>/dev/null || true
echo "$(date -Iseconds)" > "$BACKUP_DIR/backup.timestamp"
ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true
```

#### 6B.3: Upload Project Source

Upload via SFTP (or `git pull` if `.git/` exists on server), excluding `node_modules/`, `.venv/`, `.git/`, `.next/`, `dist/`, `build/`.

#### 6B.4: Generate Docker Files (If Needed)

Select template based on project type:
- Python backend → `Dockerfile.python.tpl`
- Node.js frontend → `Dockerfile.node.tpl`
- Fullstack → `Dockerfile.fullstack.tpl`

Generate `docker-compose.yml` from `docker-compose.tpl` and `.dockerignore` if missing.

#### 6B.5: Handle systemd-to-Docker Migration

If existing systemd services detected, stop and backup them before Docker deployment.

#### 6B.6: Build and Start Containers

```bash
cd "{{PROJECT_DIR}}"
docker compose build --no-cache
docker compose down 2>/dev/null || true
docker compose up -d
```

Wait up to 90s for all containers to become healthy, then verify HTTP endpoints.

### Phase 6C: Nginx Configuration

> **Skip this phase** if user chose "Skip Nginx" in Phase 4 or Nginx is not installed.

#### 6C.1: SSL Detection

Check in order:
1. Let's Encrypt: `/etc/letsencrypt/live/{{PRIMARY_DOMAIN}}/fullchain.pem`
2. Existing Nginx configs: `ssl_certificate` directives
3. Common locations: `/etc/ssl/certs/`, `/etc/nginx/ssl/`

#### 6C.2: Idempotent Check

If Nginx config exists with version marker `# {{PROJECT_NAME}} nginx config v1`, ask before overwriting.

#### 6C.3: Install Nginx Config

1. Backup existing config (timestamped `.bak`)
2. Select template: `site-https.tpl` (SSL found) or `site-http.tpl` (no SSL)
3. Render template with project variables
4. Write to `/etc/nginx/sites-available/{{NGINX_SITE_NAME}}`
5. Symlink to `/etc/nginx/sites-enabled/`
6. Clean duplicate domain blocks from default site
7. Test: `nginx -t`
8. If test passes: `systemctl reload nginx`
9. If test fails: restore backup, report error

**Key Nginx settings for SSE/WebSocket:**
```nginx
proxy_buffering off;
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
chunked_transfer_encoding on;
proxy_set_header Connection "upgrade";
proxy_set_header Upgrade $http_upgrade;
```

---

## Phase 7: Post-Deploy Verification

### Step 7.1: Select Verification Tier

```
AskUserQuestion:
  question: "Select verification level:"
  candidates:
    - "Quick verification (health checks + service status)"
    - "Full verification (all checks including SSL, logs, resources)"
    - "Skip verification"
```

In auto mode, run full verification.

### Step 7.2: Quick Verification

| # | Check | Method | Pass Criteria |
|---|-------|--------|---------------|
| 1 | Backend HTTP | `curl -sf http://localhost:{{BACKEND_PORT}}/health` | HTTP 2xx |
| 2 | Frontend HTTP | `curl -sf http://localhost:{{FRONTEND_PORT}}/` | HTTP 2xx |
| 3 | Service active (systemd) | `systemctl is-active` | "active" |
| 3 | Container running (Docker) | `docker compose ps` | State = "running" |
| 4 | Port listening | `ss -tlnH sport = :PORT` | Port open |

### Step 7.3: Full Verification (Additional)

| # | Check | Method | Pass Criteria |
|---|-------|--------|---------------|
| 5 | Nginx config valid | `nginx -t` | Exit 0 |
| 6 | Domain reachable | `curl -sf http://{{DOMAIN}}/` | HTTP 2xx |
| 7 | SSL certificate | `openssl s_client` | Valid, not expired |
| 8 | Watchdog active (systemd) | `systemctl is-active watchdog.timer` | "active" |
| 9 | Log errors (systemd) | `journalctl -n 50` | No ERROR lines |
| 9 | Log errors (Docker) | `docker compose logs --tail 50` | No ERROR lines |
| 10 | Disk space | `df -h` | >10% free |
| 11 | Memory | `free -h` | >500MB available |

**Deploy-mode-conditional checks:** Checks 3, 8, and 9 differ between systemd and Docker. The SKILL selects the appropriate command set based on `deploy_mode` before sending via `ssh_exec` — these are runtime conditionals, not template variables.

### Step 7.4: Verification Report

```
╔══════════════════════════════════════════════════╗
║  Deployment Verification Report                   ║
║  Server: {{HOST}} ({{REMOTE_DIR}})               ║
║  Mode: {{DEPLOY_MODE}}                            ║
╠══════════════════════════════════════════════════╣
║  [✓/✗] Check results line by line                 ║
╠══════════════════════════════════════════════════╣
║  Result: ALL PASSED / N CHECKS FAILED             ║
╚══════════════════════════════════════════════════╝
```

### Step 7.5: Failure Handling

If any checks failed:

1. Collect diagnostic info (service status, journal logs, port usage, Nginx errors)
2. Present failure report

```
AskUserQuestion:
  question: "Deployment verification FAILED. {{FAILED_CHECKS}}\n\nWhat would you like to do?"
  candidates:
    - "Retry deployment (re-run from build step)"
    - "Rollback to previous state"
    - "Show detailed logs for manual debugging"
    - "Skip this server and continue"  # multi-server only
```

### Step 7.6: Rollback (systemd)

```bash
BACKUP_DIR=$(ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ | head -1)
systemctl stop {{PROJECT_NAME}}-*.service {{PROJECT_NAME}}-*.timer 2>/dev/null || true
cp "$BACKUP_DIR"/{{PROJECT_NAME}}-*.service /etc/systemd/system/ 2>/dev/null || true
cp "$BACKUP_DIR"/{{PROJECT_NAME}}-*.timer /etc/systemd/system/ 2>/dev/null || true
[ -f "$BACKUP_DIR/{{NGINX_SITE_NAME}}" ] && cp "$BACKUP_DIR/{{NGINX_SITE_NAME}}" /etc/nginx/sites-available/ && nginx -t && systemctl reload nginx
systemctl daemon-reload
systemctl start {{PROJECT_NAME}}-backend.service {{PROJECT_NAME}}-frontend.service {{PROJECT_NAME}}-watchdog.timer 2>/dev/null || true
```

### Step 7.7: Rollback (Docker)

```bash
BACKUP_DIR=$(ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ | head -1)
cd "{{PROJECT_DIR}}"
docker compose down 2>/dev/null || true
cp "$BACKUP_DIR"/docker-compose.yml "$BACKUP_DIR"/Dockerfile* . 2>/dev/null || true
[ -f "$BACKUP_DIR/{{NGINX_SITE_NAME}}" ] && cp "$BACKUP_DIR/{{NGINX_SITE_NAME}}" /etc/nginx/sites-available/ && nginx -t && systemctl reload nginx
docker compose up -d
```

### Step 7.8: Multi-Server Summary

For batch deployments:

```
╔══════════════════════════════════════════════════╗
║  Multi-Server Verification Summary                ║
╠══════════════════════════════════════════════════╣
║  server-1 (10.0.1.10):  ✓ ALL PASSED             ║
║  server-2 (10.0.1.11):  ✓ ALL PASSED             ║
║  server-3 (10.0.1.12):  ✗ FAILED (2 checks)      ║
╠══════════════════════════════════════════════════╣
║  Total: 2/3 servers fully deployed                ║
╚══════════════════════════════════════════════════╝
```

Handle each failed server individually.

---

## Phase 8: Summary & Handoff

### Step 8.1: Deployment Report

```
╔══════════════════════════════════════════════════╗
║  Deployment Complete                              ║
╠══════════════════════════════════════════════════╣
║  Project:  {{PROJECT_NAME}}                       ║
║  Server:   {{HOST}} ({{REMOTE_DIR}})             ║
║  Mode:     {{DEPLOY_MODE}}                        ║
║  Services:                                        ║
║    - {{PROJECT_NAME}}-backend  (port {{BP}})     ║
║    - {{PROJECT_NAME}}-frontend (port {{FP}})     ║
║    - {{PROJECT_NAME}}-watchdog (every {{INT}}s)  ║
║  Nginx:    {{DOMAIN}} → localhost:{{FP}}         ║
║  SSL:      {{SSL_STATUS}}                         ║
╠══════════════════════════════════════════════════╣
║  Generated files:                                 ║
║  LOCAL:   ops/config.env, install.sh, deploy.sh  ║
║           uninstall.sh, status.sh, logs.sh       ║
║           healthcheck.sh, README.md              ║
║  SERVER:  same files at {{REMOTE_DIR}}/ops/      ║
╠══════════════════════════════════════════════════╣
║  Quick commands:                                  ║
║    Status:   ssh {{USER}}@{{HOST}} ./ops/status.sh║
║    Redeploy: ssh {{USER}}@{{HOST}} ./ops/deploy.sh║
║    Logs:     ssh {{USER}}@{{HOST}} ./ops/logs.sh  ║
║    Uninstall: ssh {{USER}}@{{HOST}} sudo ./ops/uninstall.sh║
╚══════════════════════════════════════════════════╝
```

### Step 8.2: Next Steps

```
AskUserQuestion:
  question: "What would you like to do next?"
  candidates:
    - "Save server config to memory for future deployments"
    - "Deploy to another server"
    - "Done — end session"
```

If "Save to memory": save server host, username, key path, remote dir, and project name to Claude Code memory for future sessions.

If "Deploy to another server": loop back to Phase 3.

---

## Error Recovery

At any phase, if an unrecoverable error occurs:

1. Report the error clearly with context
2. Offer to retry the current step
3. Offer to go back to a previous phase
4. Never silently skip steps

```
AskUserQuestion:
  question: "An error occurred during {{PHASE}}: {{ERROR}}\n\nWhat would you like to do?"
  candidates:
    - "Retry this step"
    - "Go back to {{PREVIOUS_PHASE}}"
    - "Abort deployment"
```

## Security Rules

- Never store passwords in files or memory — use SSH keys or env vars
- Never log passwords or private keys in output
- SSH host key policy: AutoAddPolicy (acceptable for trusted deployment targets)
- Pre-flight warns on first connection to unknown hosts
- Generated scripts run under the deploy user (not root) except for systemd management commands
