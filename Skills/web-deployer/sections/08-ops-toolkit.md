<!-- Section: Ops Toolkit Generation -->
<!-- Author: google-dev-04 -->
<!-- Integrates into: SKILL.md Phase 5 (Template Rendering & Ops Generation) -->
<!-- Consumed by: dev-05 (systemd deployment), dev-06 (nginx config), dev-07 (verification), dev-08 (integrator) -->
<!-- Depends on: sections/01-project-analysis.md (ProjectProfile), sections/03-server-connection.md (SSH/SFTP helpers) -->

### Phase 5: Template Rendering & Ops Generation

Generate a complete, independent `ops/` toolkit in the user's project directory and upload it to each target server. Every script reads `config.env` for project-specific values and works without Claude Code or the SKILL.

---

#### Step 1: Determine Ops File Manifest

Based on the `ProjectProfile` (produced in Phase 2) and the deployment mode chosen in Phase 4, compute the exact list of files to generate. The manifest varies by project type and deployment mode.

**Base manifest (always generated):**

| File | Purpose |
|---|---|
| `ops/config.env` | Centralized configuration. All scripts source this file. |
| `ops/deploy.sh` | One-command redeploy: git pull, install deps, build, restart services |
| `ops/install.sh` | Register systemd services, watchdog timer, logrotate, and Nginx config |
| `ops/install-deps.sh` | Install project dependencies (pip, npm/yarn/pnpm, system packages) |
| `ops/uninstall.sh` | Stop and remove all registered services, logrotate, Nginx config |
| `ops/status.sh` | Display status of all services, ports, health checks, watchdog counters |
| `ops/logs.sh` | View journalctl logs per service with filtering and follow mode |
| `ops/healthcheck.sh` | Watchdog-invoked HTTP health check with failure counter and auto-restart |
| `ops/README.md` | Usage documentation (language-aware: English or Chinese per Phase 1 choice) |

**Systemd template files (generated when `deploy_mode == "systemd"`):**

| File | Condition |
|---|---|
| `ops/templates/{{PROJECT_NAME}}-backend.service` | `project_profile.backend.detected == true` |
| `ops/templates/{{PROJECT_NAME}}-frontend.service` | `project_profile.frontend.detected == true` |
| `ops/templates/{{PROJECT_NAME}}-watchdog.service` | Always (watchdog monitors whichever services exist) |
| `ops/templates/{{PROJECT_NAME}}-watchdog.timer` | Always |
| `ops/templates/{{PROJECT_NAME}}-logrotate` | Always |
| `ops/templates/{{PROJECT_NAME}}-nginx` | `server_config.nginx_domain` is non-empty AND SSL certs detected |
| `ops/templates/{{PROJECT_NAME}}-nginx-http` | `server_config.nginx_domain` is non-empty AND no SSL certs |

**Docker-specific scripts (generated when `deploy_mode == "docker"`):**

| File | Purpose |
|---|---|
| `ops/docker-deploy.sh` | Build images and bring up containers via docker-compose |
| `ops/docker-status.sh` | Show running container status, ports, resource usage |
| `ops/docker-logs.sh` | Tail container logs with service filtering |
| `ops/docker-stop.sh` | Gracefully stop and remove containers |

Monolith projects (`project_type == "monolith"` or `"frontend_only"` or `"backend_only"`) generate only the relevant service template (no frontend template for backend-only, etc.).

---

#### Step 2: Resolve Template Variables

Collect all variables needed for template rendering. Variables come from three sources in priority order:

1. **User overrides** from Phase 4 deployment plan confirmation (highest priority)
2. **Auto-detected values** from `ProjectProfile` (Phase 2)
3. **Sensible defaults** (lowest priority)

Build the variable map as a flat dictionary:

```
template_vars = {
    # From ProjectProfile
    "PROJECT_NAME":        project_profile.project_name,          # e.g., "my-webapp"
    "PROJECT_DIR":         server_config.remote_project_dir,      # e.g., "/home/deploy/my-webapp"
    "PROJECT_DIR_LOCAL":   project_profile.project_dir,           # e.g., "/Users/dev/my-webapp"

    # Backend (only if detected)
    "BACKEND_PORT":        project_profile.backend.port,          # e.g., 5000
    "BACKEND_ENTRY":       project_profile.backend.entry_point,   # e.g., "app.py"
    "BACKEND_RUNTIME":     project_profile.backend.runtime,       # "python" | "node"
    "BACKEND_FRAMEWORK":   project_profile.backend.framework,     # "flask" | "django" | "express" ...
    "BACKEND_PROD_CMD":    project_profile.backend.production_command,  # e.g., "gunicorn -w 4 -b 0.0.0.0:5000 app:app"
    "BACKEND_SUBDIR":      project_profile.backend.subdirectory,  # "backend/" | "."
    "BACKEND_HEALTH_URL":  "http://localhost:{BACKEND_PORT}/health",
    "VENV_PYTHON":         "{PROJECT_DIR}/{BACKEND_SUBDIR}/.venv/bin/python" if backend.runtime == "python" else "",
    "REQUIREMENTS_FILE":   project_profile.backend.requirements_file,

    # Frontend (only if detected)
    "FRONTEND_PORT":       project_profile.frontend.port,         # e.g., 3000
    "FRONTEND_FRAMEWORK":  project_profile.frontend.framework,    # "nextjs" | "vue" | "react" ...
    "FRONTEND_BUILD_CMD":  project_profile.frontend.build_command, # e.g., "npm run build"
    "FRONTEND_BUILD_OUTPUT":  project_profile.frontend.build_output, # e.g., "out" | ".next" | "dist"
    "FRONTEND_SUBDIR":     project_profile.frontend.subdirectory, # "frontend/" | "."
    "FRONTEND_HEALTH_URL": "http://localhost:{FRONTEND_PORT}/",
    "PACKAGE_MANAGER":     project_profile.frontend.package_manager, # "npm" | "yarn" | "pnpm"

    # Server runtime (from Phase 3 pre-flight)
    "RUN_USER":            server_config.username,
    "RUN_GROUP":           server_config.user_group or server_config.username,
    "NODE_BIN":            server_config.node_path or "",         # detected during pre-flight
    "PATH_DIRS":           server_config.path_dirs,               # full PATH for systemd Environment=

    # Watchdog
    "WATCHDOG_INTERVAL":   deployment_plan.watchdog_interval or "60",
    "WATCHDOG_FAIL_THRESHOLD": deployment_plan.watchdog_threshold or "3",
    "WATCHDOG_STATE_DIR":  "/tmp",

    # Nginx
    "NGINX_DOMAIN":        server_config.nginx_domain or "",      # e.g., "example.com www.example.com"
    "NGINX_SITE_NAME":     project_profile.project_name,          # filename in sites-available
    "NGINX_SSL_CERT":      server_config.ssl_cert_path or "",
    "NGINX_SSL_KEY":       server_config.ssl_key_path or "",

    # Logging
    "LOG_DIR":             "logs",
    "LOG_MAX_SIZE":        "50M",
    "LOG_ROTATE_COUNT":    "7",

    # Metadata
    "DEPLOY_TIMESTAMP":    current UTC timestamp in ISO 8601,
    "DEPLOY_MODE":         "systemd" | "docker",

    # Conditional flags (used for {{IF ...}} blocks)
    "BACKEND_DETECTED":    "true" if backend.detected else "false",
    "FRONTEND_DETECTED":   "true" if frontend.detected else "false",
    "HAS_NGINX":           "true" if nginx_domain non-empty else "false",
    "HAS_SSL":             "true" if ssl_cert and ssl_key else "false",
}
```

**Validation rule:** Before rendering, iterate through all `.tpl` files in `templates/ops/`, `templates/systemd/`, `templates/nginx/`, and `templates/docker/`. Extract every `{{VARIABLE}}` placeholder. Verify that each placeholder exists in `template_vars`. If any are missing, halt and report the missing variables to the user before proceeding.

---

#### Step 3: Template Rendering Engine

The SKILL uses the `{{VARIABLE}}` placeholder syntax. Rendering is a two-pass process:

**Pass 1: Conditional Block Resolution**

Process `{{IF <FLAG>}}...{{ENDIF <FLAG>}}` blocks. If the flag resolves to `"false"` or empty string, remove the entire block (including the IF/ENDIF markers). If `"true"`, keep the content but strip the IF/ENDIF markers.

```
Conditional syntax:
    {{IF BACKEND_DETECTED}}
    BACKEND_PORT={{BACKEND_PORT}}
    {{ENDIF BACKEND_DETECTED}}

When BACKEND_DETECTED == "true":
    BACKEND_PORT=5000

When BACKEND_DETECTED == "false":
    (entire block removed)
```

**Pass 2: Variable Substitution**

Replace all remaining `{{VARIABLE}}` placeholders with their resolved values from `template_vars`. Use exact string replacement (not regex) to avoid issues with special characters in paths or commands.

The rendering implementation reads each `.tpl` file from the SKILL's `templates/` directory using `Read`, performs both passes in memory, and writes the output using `Write`.

```
For each file in the ops manifest:
    1. Read the corresponding .tpl file from web-deployer/templates/
    2. Apply Pass 1 (conditional block resolution)
    3. Apply Pass 2 (variable substitution)
    4. Write the rendered output to ops/{filename}
```

**Important:** The SKILL reads template files from its own `templates/` directory (inside `web-deployer/`), NOT from the user's project. The rendered output goes into the user's project `ops/` directory.

---

#### Step 4: config.env Generation

`config.env` is the single source of truth for all ops scripts. Generate it by rendering the `config.env.tpl` template with the resolved variable map.

**Generated config.env structure:**

```bash
# =============================================================================
# {{PROJECT_NAME}} Service Configuration
# Read by install.sh — re-run install.sh after modifying this file.
# Generated by web-deployer skill on {{DEPLOY_TIMESTAMP}}
# =============================================================================

# Project
PROJECT_NAME={{PROJECT_NAME}}

# Node.js binary path (auto-detected if empty)
# NODE_BIN=/path/to/node

# Ports
{{IF BACKEND_DETECTED}}
BACKEND_PORT={{BACKEND_PORT}}
{{ENDIF BACKEND_DETECTED}}
{{IF FRONTEND_DETECTED}}
FRONTEND_PORT={{FRONTEND_PORT}}
{{ENDIF FRONTEND_DETECTED}}

# Watchdog
WATCHDOG_INTERVAL={{WATCHDOG_INTERVAL}}
WATCHDOG_FAIL_THRESHOLD={{WATCHDOG_FAIL_THRESHOLD}}
WATCHDOG_STATE_DIR={{WATCHDOG_STATE_DIR}}

# Nginx reverse proxy (leave NGINX_DOMAIN empty to skip)
NGINX_DOMAIN="{{NGINX_DOMAIN}}"
NGINX_SITE_NAME="{{NGINX_SITE_NAME}}"

# Logging
LOG_DIR={{LOG_DIR}}
LOG_MAX_SIZE={{LOG_MAX_SIZE}}
LOG_ROTATE_COUNT={{LOG_ROTATE_COUNT}}

# Health check endpoints
{{IF BACKEND_DETECTED}}
BACKEND_HEALTH_URL="{{BACKEND_HEALTH_URL}}"
{{ENDIF BACKEND_DETECTED}}
{{IF FRONTEND_DETECTED}}
FRONTEND_HEALTH_URL="{{FRONTEND_HEALTH_URL}}"
{{ENDIF FRONTEND_DETECTED}}

# Service commands (used by deploy.sh and install.sh)
{{IF BACKEND_DETECTED}}
BACKEND_PROD_CMD="{{BACKEND_PROD_CMD}}"
BACKEND_SUBDIR="{{BACKEND_SUBDIR}}"
BACKEND_RUNTIME="{{BACKEND_RUNTIME}}"
{{ENDIF BACKEND_DETECTED}}
{{IF FRONTEND_DETECTED}}
FRONTEND_BUILD_CMD="{{FRONTEND_BUILD_CMD}}"
FRONTEND_BUILD_OUTPUT="{{FRONTEND_BUILD_OUTPUT}}"
FRONTEND_SUBDIR="{{FRONTEND_SUBDIR}}"
PACKAGE_MANAGER="{{PACKAGE_MANAGER}}"
{{ENDIF FRONTEND_DETECTED}}
```

**Server-specific config.env:** When deploying to remote servers, the SKILL generates a second config.env with server-specific paths. The differences are:

| Variable | Local Value | Server Value |
|---|---|---|
| `PROJECT_DIR` (implicit) | `/Users/dev/my-webapp` | `/home/deploy/my-webapp` |
| `NODE_BIN` | (commented out) | `/home/deploy/.nvm/versions/node/v20.11.0/bin/node` (from pre-flight) |
| `VENV_PYTHON` | `./backend/.venv/bin/python` | `/home/deploy/my-webapp/backend/.venv/bin/python` |

The local config.env uses relative paths where possible; the server config.env uses absolute paths resolved during pre-flight checks.

---

#### Step 5: Script Generalization — InkClaw to Generic

Every InkClaw-specific reference is replaced with a `config.env`-driven equivalent. This table documents all transformations applied during template rendering:

| InkClaw Hardcoded Pattern | Generalized Replacement | Affected Scripts |
|---|---|---|
| `inkclaw-backend.service` | `${PROJECT_NAME}-backend.service` | install.sh, uninstall.sh, status.sh, logs.sh |
| `inkclaw-frontend.service` | `${PROJECT_NAME}-frontend.service` | install.sh, uninstall.sh, status.sh, logs.sh |
| `inkclaw-watchdog.service` | `${PROJECT_NAME}-watchdog.service` | install.sh, uninstall.sh, status.sh |
| `inkclaw-watchdog.timer` | `${PROJECT_NAME}-watchdog.timer` | install.sh, uninstall.sh, status.sh |
| `inkclaw` (logrotate file) | `${PROJECT_NAME}` in `/etc/logrotate.d/` | install.sh, uninstall.sh |
| `inkclaw` (nginx site file) | `${NGINX_SITE_NAME}` in `/etc/nginx/sites-available/` | install.sh, uninstall.sh |
| `if [[ ! -f "$PROJECT_DIR/backend/app.py" ]]` | Dynamic check using `BACKEND_SUBDIR` and `BACKEND_ENTRY` from config.env | install.sh |
| `VENV_PYTHON="$PROJECT_DIR/backend/.venv/bin/python"` | `VENV_PYTHON` resolved from config.env or auto-detected at install time | install.sh |
| `if [[ ! -d "$PROJECT_DIR/out" ]]` | `FRONTEND_BUILD_OUTPUT` from config.env (e.g., `out`, `.next`, `dist`) | install.sh |
| Flask-specific `ExecStart=...gunicorn...` | `BACKEND_PROD_CMD` from config.env (framework-agnostic) | backend.service template |
| `"InkClaw"` in log messages / banner text | `${PROJECT_NAME}` everywhere | all scripts |
| `/tmp/inkclaw-watchdog-*-failures` | `/tmp/${PROJECT_NAME}-watchdog-*-failures` | healthcheck.sh, status.sh |
| `# InkClaw nginx config v1` version marker | `# ${PROJECT_NAME} nginx config v1` | install.sh (Nginx section) |
| `USER_DATA_DIR=/home/$RUN_USER/.inkclaw-data` | `USER_DATA_DIR=/home/$RUN_USER/.${PROJECT_NAME}-data` | install.sh, config.env |

**Key abstractions replacing hardcoded logic:**

1. **Service list:** Instead of hardcoding "backend" and "frontend", each script reads which services exist from config.env (`BACKEND_DETECTED`, `FRONTEND_DETECTED`). Monolith and single-service projects only register the relevant services.

2. **Health endpoints:** Configurable per-service health URLs in config.env (`BACKEND_HEALTH_URL`, `FRONTEND_HEALTH_URL`). Default: `http://localhost:{PORT}/health` for backends, `http://localhost:{PORT}/` for frontends.

3. **Build commands:** `FRONTEND_BUILD_CMD` in config.env replaces the hardcoded `npm run build`. Supports `yarn build`, `pnpm build`, etc.

4. **Entry points:** `BACKEND_PROD_CMD` provides the complete production command for any framework. `install.sh` writes this directly into the systemd `ExecStart=` line.

---

#### Step 6: Naming Convention

All generated files use `{{PROJECT_NAME}}` as the identifying prefix. The project name is:

1. Auto-inferred from `package.json` `.name` field, or the project directory name as fallback
2. Converted to kebab-case (lowercase, hyphens, no underscores or special characters)
3. Confirmed by the user during Phase 2 (Step 10)

**Naming applied to:**

| Artifact | Naming Pattern | Example (`PROJECT_NAME=my-webapp`) |
|---|---|---|
| systemd backend service | `{PROJECT_NAME}-backend.service` | `my-webapp-backend.service` |
| systemd frontend service | `{PROJECT_NAME}-frontend.service` | `my-webapp-frontend.service` |
| systemd watchdog service | `{PROJECT_NAME}-watchdog.service` | `my-webapp-watchdog.service` |
| systemd watchdog timer | `{PROJECT_NAME}-watchdog.timer` | `my-webapp-watchdog.timer` |
| logrotate config | `/etc/logrotate.d/{PROJECT_NAME}` | `/etc/logrotate.d/my-webapp` |
| Nginx site config | `/etc/nginx/sites-available/{NGINX_SITE_NAME}` | `/etc/nginx/sites-available/my-webapp` |
| Watchdog state files | `/tmp/{PROJECT_NAME}-watchdog-{service}-failures` | `/tmp/my-webapp-watchdog-backend-failures` |
| ops/templates/ files | `{PROJECT_NAME}-*.service`, `{PROJECT_NAME}-*` | `my-webapp-backend.service`, `my-webapp-logrotate` |
| Docker containers | `{PROJECT_NAME}-backend`, `{PROJECT_NAME}-frontend` | `my-webapp-backend`, `my-webapp-frontend` |
| Docker Compose project | `{PROJECT_NAME}` | `my-webapp` |

---

#### Step 7: Local Placement

Write all rendered files to the user's project directory under `ops/`.

**Directory creation:**

```
Use Bash to create the ops directory structure:
    mkdir -p {project_profile.project_dir}/ops/templates
```

**File writing order:**

1. `ops/config.env` — write first (other scripts depend on it for validation)
2. `ops/templates/*` — write all systemd/logrotate/nginx template files
3. `ops/install.sh` — write the main installer
4. `ops/install-deps.sh` — write dependency installer
5. `ops/uninstall.sh` — write uninstaller
6. `ops/status.sh` — write status checker
7. `ops/logs.sh` — write log viewer
8. `ops/healthcheck.sh` — write watchdog health check
9. `ops/deploy.sh` — write one-command deploy script
10. `ops/README.md` — write generated documentation (last, since it references all other files)

If `deploy_mode == "docker"`, also write:

11. `ops/docker-deploy.sh`
12. `ops/docker-status.sh`
13. `ops/docker-logs.sh`
14. `ops/docker-stop.sh`

**Set executable permissions on all .sh files:**

```
Use Bash:
    chmod +x {project_profile.project_dir}/ops/*.sh
```

**Verify local placement:**

After writing all files, run a quick validation:

```
Use Bash:
    ls -la {project_profile.project_dir}/ops/
    ls -la {project_profile.project_dir}/ops/templates/
```

Confirm that all files in the manifest were written and have the expected size (> 0 bytes).

---

#### Step 8: Remote Upload via SFTP

Upload the generated `ops/` directory to each target server. Use the `sftp_upload` helper from sections/03-server-connection.md.

**For each server in `server_contexts`:**

```python
# 1. Ensure the remote project directory exists
sftp_makedirs(sftp, f"{server_config.remote_project_dir}/ops/templates")

# 2. Upload the entire local ops/ directory
sftp_upload(
    ssh=ctx["ssh"],
    local_paths=f"{project_profile.project_dir}/ops",
    remote_dir=server_config.remote_project_dir,
    progress=True
)

# 3. Overwrite config.env with server-specific values
#    (The local config.env has local paths; the server needs absolute remote paths)
sftp_upload(
    ssh=ctx["ssh"],
    local_paths=server_specific_config_env_path,
    remote_dir=f"{server_config.remote_project_dir}/ops",
    progress=True
)

# 4. Set executable permissions on all .sh files
ssh_exec(ctx["ssh"], f"chmod +x {server_config.remote_project_dir}/ops/*.sh")

# 5. Verify upload
result = ssh_exec(ctx["ssh"], f"ls -la {server_config.remote_project_dir}/ops/")
# Check that the file count matches the manifest
```

**Server-specific config.env generation:**

Before uploading, generate a temporary server-specific `config.env` with absolute paths:

```python
import tempfile, os

server_config_env = render_config_env(template_vars, overrides={
    # Replace local PROJECT_DIR with remote PROJECT_DIR
    "PROJECT_DIR": server_config.remote_project_dir,
    # Use the node binary path detected during pre-flight
    "NODE_BIN": ctx["preflight"]["node_path"],
    # Absolute venv path on server
    "VENV_PYTHON": f"{server_config.remote_project_dir}/{project_profile.backend.subdirectory}/.venv/bin/python"
        if project_profile.backend.runtime == "python" else "",
})

# Write to temp file, upload, clean up
tmp_path = os.path.join(tempfile.gettempdir(), "config.env")
with open(tmp_path, "w") as f:
    f.write(server_config_env)
```

**Permission model on server:**

| File | Owner | Mode | Reason |
|---|---|---|---|
| `ops/*.sh` | deploy user | `0755` (`rwxr-xr-x`) | Executable by owner and group |
| `ops/config.env` | deploy user | `0644` (`rw-r--r--`) | Readable but not executable |
| `ops/README.md` | deploy user | `0644` | Documentation, read-only |
| `ops/templates/*` | deploy user | `0644` | Templates processed by install.sh, not executed directly |

---

#### Step 9: deploy.sh — One-Command Redeploy Script

`deploy.sh` is a new script (not present in the original InkClaw ops) that provides a single command for redeployment after initial setup.

**Workflow:**

```
deploy.sh [--skip-build] [--skip-deps] [--skip-install]

Step 1: Resolve project directory (same as install.sh: SCRIPT_DIR -> PROJECT_DIR)
Step 2: Source config.env
Step 3: git pull (if .git directory exists; skip if not a git repo)
Step 4: Install dependencies (unless --skip-deps)
    - If BACKEND_DETECTED:
        - If BACKEND_RUNTIME == "python":
            pip install -r {REQUIREMENTS_FILE}
        - If BACKEND_RUNTIME == "node":
            {PACKAGE_MANAGER} install
    - If FRONTEND_DETECTED:
        {PACKAGE_MANAGER} install
Step 5: Build frontend (unless --skip-build)
    - If FRONTEND_DETECTED:
        cd {FRONTEND_SUBDIR} && {FRONTEND_BUILD_CMD}
    - Verify build output directory exists after build
Step 6: Run install.sh to update systemd units (unless --skip-install)
    - sudo ./ops/install.sh
Step 7: Wait for services to be healthy
    - Poll BACKEND_HEALTH_URL (if defined) for up to 30 seconds
    - Poll FRONTEND_HEALTH_URL (if defined) for up to 30 seconds
Step 8: Print summary (service status, health check results)
```

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | All steps succeeded, services healthy |
| 1 | Git pull failed |
| 2 | Dependency installation failed |
| 3 | Build failed |
| 4 | install.sh failed |
| 5 | Services not healthy after 30s timeout |

**deploy.sh includes the same color/logging helpers** (`log`, `ok`, `warn`, `error`, `die`) as all other ops scripts for visual consistency.

---

#### Step 10: Docker-Specific Ops Scripts

When `deploy_mode == "docker"`, generate four additional scripts. These scripts assume `docker` and `docker-compose` (or `docker compose` plugin) are available on the server.

**docker-deploy.sh:**

```
docker-deploy.sh [--no-cache] [--pull]

Step 1: Source config.env
Step 2: git pull (if .git repo)
Step 3: docker-compose build [--no-cache if flag passed]
Step 4: docker-compose up -d
Step 5: Wait for containers to be healthy (docker inspect --format)
Step 6: Print container status summary
```

**docker-status.sh:**

```
docker-status.sh

Step 1: Source config.env
Step 2: docker-compose ps
Step 3: For each container, show:
    - Container name, image, status, ports
    - CPU and memory usage (docker stats --no-stream)
    - Last 5 log lines
```

**docker-logs.sh:**

```
docker-logs.sh [service] [-f] [-n LINES]

Step 1: Source config.env
Step 2: If service specified:
    docker-compose logs [--follow] [--tail=LINES] {service}
Step 3: If no service:
    docker-compose logs [--follow] [--tail=LINES]
```

**docker-stop.sh:**

```
docker-stop.sh [--remove-volumes]

Step 1: Source config.env
Step 2: docker-compose down [--volumes if flag passed]
Step 3: Print stopped container summary
```

All Docker scripts detect whether to use `docker-compose` (standalone) or `docker compose` (plugin) by checking which is available:

```bash
if command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DC="docker compose"
else
    die "Neither docker-compose nor docker compose found."
fi
```

---

#### Step 11: ops/README.md Generation

Generate a human-readable README.md for the ops directory. The language follows the user's choice from Phase 1.

**README structure:**

```markdown
# {PROJECT_NAME} Ops Toolkit

## Prerequisites
- OS: Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- Runtime: {detected runtimes}
- Project: built and ready (build artifacts present)
- Permissions: install/uninstall require sudo; status/logs do not

## Quick Start
1. Install dependencies: ./ops/install-deps.sh
2. Build project: {FRONTEND_BUILD_CMD}
3. Register services: sudo ./ops/install.sh
4. One-command redeploy: ./ops/deploy.sh

## Available Scripts
| Script | Purpose | Requires sudo |
|--------|---------|---------------|
{table of all generated scripts with one-line descriptions}

## Configuration Reference
{table of all config.env variables with descriptions and defaults}

## Architecture
{diagram showing systemd units, watchdog timer, logrotate, Nginx relationship}

## Troubleshooting
{common issues and solutions, adapted from the InkClaw README}
```

**Language-aware generation:**

```
If interaction_language == "zh" (Chinese):
    Use Chinese section headers, descriptions, and troubleshooting text
    (following the style of the original ops/README.md which is in Chinese)

If interaction_language == "en" (English):
    Use English throughout
```

The README is generated last (Step 7 file #10) because it references all other generated files and can include accurate file listings.

---

#### Step 12: .gitignore Recommendations

After generating the ops toolkit, check for a `.gitignore` file in the project root and recommend additions.

**Check:**

```
Use Read to check if {project_profile.project_dir}/.gitignore exists
```

**If .gitignore exists, suggest appending:**

```
# web-deployer ops (commit scripts, ignore server-specific config)
ops/config.env
.deploy-backups/
```

**If .gitignore does not exist, suggest creating one with at minimum:**

```
ops/config.env
.deploy-backups/
```

**Rationale:**
- `ops/config.env` contains server-specific values (ports, domains, paths) that differ per environment. It should NOT be committed; each server has its own copy.
- `.deploy-backups/` contains rollback snapshots created during deployment.
- The ops scripts themselves (`.sh` files, templates, README.md) SHOULD be committed. They are project infrastructure, not ephemeral artifacts.

**Present the recommendation to the user via AskUserQuestion:**

```
If interaction_language == "en":
    "The ops toolkit has been generated. I recommend adding these entries to .gitignore
     to avoid committing server-specific configuration:

     ops/config.env
     .deploy-backups/

     The ops scripts themselves (install.sh, deploy.sh, etc.) should be committed
     as they are part of your project's deployment infrastructure.

     A) Add to .gitignore automatically
     B) Skip — I'll handle it manually"

If interaction_language == "zh":
    (equivalent in Chinese)
```

If user selects A, use `Edit` to append the entries to `.gitignore` (or `Write` if the file does not exist).

---

#### Step 13: Validation — Verify Generated Scripts

After local placement (Step 7), run syntax checks on all generated shell scripts to catch rendering errors (unclosed quotes, unresolved placeholders, missing variables).

**Validation checks:**

```
For each .sh file in ops/:
    1. bash -n {file}
       (Syntax check only, does not execute. Exit code 0 = valid syntax.)

    2. Grep for unresolved placeholders:
       grep -n '{{' {file}
       (Any remaining {{...}} means a template variable was not resolved.)

    3. Grep for empty critical values:
       grep -n '=""$' {file}
       (Catches cases where a required variable resolved to empty string.)
```

**Implementation:**

```
Use Bash:
    cd {project_profile.project_dir}
    errors=0
    for script in ops/*.sh; do
        if ! bash -n "$script" 2>/dev/null; then
            echo "SYNTAX ERROR in $script"
            bash -n "$script"
            errors=$((errors + 1))
        fi
        if grep -qn '{{' "$script"; then
            echo "UNRESOLVED PLACEHOLDER in $script:"
            grep -n '{{' "$script"
            errors=$((errors + 1))
        fi
    done
    echo "Validation complete. Errors: $errors"
```

**If validation fails:**

1. Report the specific errors to the user with file names and line numbers
2. Attempt auto-fix: re-read the template, re-render with corrected variables
3. If auto-fix fails, present the errors and ask the user to provide the missing values

**If validation passes:**

Report success and proceed to Phase 6 (Remote Deployment Execution).

```
If interaction_language == "en":
    "Ops toolkit generated and validated successfully.
     {N} scripts written to {project_dir}/ops/
     All scripts pass syntax check, no unresolved placeholders.
     Ready to proceed with deployment."

If interaction_language == "zh":
    (equivalent in Chinese)
```

---

#### Phase 5 Complete — Gate

Phase 5 is complete when ALL of the following are true:

- [ ] All files in the ops manifest have been rendered and written to `{project_dir}/ops/`
- [ ] All `.sh` files pass `bash -n` syntax validation
- [ ] No unresolved `{{...}}` placeholders remain in any generated file
- [ ] `config.env` contains all required variables for the detected project type
- [ ] `ops/README.md` has been generated in the correct language
- [ ] `.gitignore` recommendation has been presented to the user
- [ ] For each server in `server_contexts`: ops/ has been uploaded via SFTP with correct permissions

Proceed to Phase 6 (Remote Deployment Execution) or, if multi-server mode, trigger parallel deployment agents.
