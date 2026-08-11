### Phase 5: Template Rendering

Render all `.tpl` template files into project-specific deployment scripts and configuration files using the ProjectProfile (from Phase 2) and server information (from Phase 3). This phase transforms generic templates into a fully functional `ops/` toolkit.

#### Step 1: Template Placeholder Syntax

All templates in `templates/` use these syntactic constructs:

**Simple Variable Substitution:**
```
{{VARIABLE_NAME}}
```
Every `{{VARIABLE_NAME}}` occurrence is replaced with the resolved value from the variable registry. Variables are case-sensitive and use UPPER_SNAKE_CASE.

**Conditional Blocks (inclusion):**
```bash
# {{IF CONDITION}}
# ... content included when CONDITION is truthy ...
# {{ENDIF CONDITION}}
```
A condition is "truthy" when the corresponding boolean variable evaluates to `true`, or when the corresponding string variable is non-empty. The `# ` comment prefix is part of the syntax so that unrendered templates remain valid shell/config files.

**Conditional Blocks (negation):**
```bash
# {{IF_NOT CONDITION}}
# ... content included when CONDITION is falsy ...
# {{ENDIF_NOT CONDITION}}
```

**Iteration (for multi-service):**
```bash
# {{FOR_EACH SERVICE}}
# ... repeated per service ...
# {{END_FOR_EACH}}
```
Used in advanced multi-service scenarios. Not required for standard frontend+backend or monolith projects.

#### Step 2: Variable Registry

Below is the complete variable registry. Every `{{VARIABLE}}` used across all templates is listed here with its source and default value. The SKILL must resolve ALL variables before rendering.

##### Auto-Detected Variables (from ProjectProfile, Phase 2)

| Variable | Source | Default | Description |
|---|---|---|---|
| `PROJECT_NAME` | `project_profile.project_name` | directory basename | Kebab-case project identifier used in service names, file names, paths |
| `PROJECT_DIR` | Absolute path on server | — (required) | Full path to project root on the target server |
| `RUN_USER` | SSH username or specified | SSH user | Linux user that runs the services |
| `RUN_GROUP` | Primary group of RUN_USER | RUN_USER | Linux group for file ownership |
| `FRONTEND_FRAMEWORK` | Detection result | — | One of: `nextjs`, `nuxtjs`, `react`, `vue`, `express`, `none` |
| `BACKEND_FRAMEWORK` | Detection result | — | One of: `flask`, `django`, `fastapi`, `express`, `nestjs`, `python_generic`, `none` |
| `FRONTEND_PORT` | Framework default or user override | `3000` | Port the frontend process listens on |
| `BACKEND_PORT` | Framework default or user override | `5000` | Port the backend process listens on |
| `NODE_BIN` | Resolved on server | Auto-detected | Absolute path to the Node.js binary |
| `VENV_PYTHON` | Resolved on server | Auto-detected | Absolute path to the Python venv binary |
| `BUILD_COMMAND` | From package.json or detection | `npm run build` | Command to build frontend assets |
| `FRONTEND_START` | `production_command` from profile | Framework-specific | Full ExecStart command for the frontend service |
| `BACKEND_START` | `production_command` from profile | Framework-specific | Full ExecStart command for the backend service |
| `FRONTEND_SUBDIRECTORY` | Project structure scan | `.` | Relative path from project root to frontend code |
| `BACKEND_SUBDIRECTORY` | Project structure scan | `.` | Relative path from project root to backend code |
| `FRONTEND_BUILD_OUTPUT` | Framework detection | Framework-specific | Build output directory name (e.g., `out`, `.next`, `build`, `dist`) |
| `FRONTEND_ENTRY_POINT` | Detection | `server.js` | Main file for frontend process |
| `BACKEND_ENTRY_POINT` | Detection | `app.py` | Main file for backend process (without extension for module imports) |
| `NODE_PACKAGE_MANAGER` | Detection from lockfiles | `npm` | One of: `npm`, `yarn`, `pnpm` |
| `PYTHON_PACKAGE_MANAGER` | Detection from lockfiles | `pip` | One of: `pip`, `pipenv`, `poetry`, `conda` |
| `NODE_VERSION` | Detected from .nvmrc or engines | `20` | Major Node.js version for Docker images |
| `PYTHON_VERSION` | Detected from runtime-txt or venv | `3.11` | Python version for Docker images |
| `PYTHON_MAJOR_VERSION` | Derived from PYTHON_VERSION | `3.11` | Major.minor for site-packages path |
| `DJANGO_WSGI_MODULE` | Detection from manage.py | Project name | Django WSGI module name |

##### Boolean Feature Flags (for conditional blocks)

| Variable | True When | Used In |
|---|---|---|
| `HAS_FRONTEND` | Frontend framework detected | All ops, systemd, nginx, docker templates |
| `HAS_BACKEND` | Backend framework detected | All ops, systemd, nginx, docker templates |
| `HAS_NODE` | Node.js project present | install.sh, install-deps.sh, config.env |
| `HAS_PYTHON` | Python project present | install.sh, install-deps.sh, config.env |
| `HAS_SSL` | SSL certificates detected on server | nginx/site-https, docker-compose |
| `FEATURE_WATCHDOG` | User enabled watchdog | install.sh (runtime flag, not template-time) |
| `FEATURE_NGINX` | Nginx reverse proxy enabled | docker-compose |
| `FRAMEWORK_NEXTJS` | Frontend is Next.js | Dockerfile.node, Dockerfile.fullstack |
| `FRAMEWORK_NUXTJS` | Frontend is Nuxt.js | Dockerfile.node, Dockerfile.fullstack |
| `FRAMEWORK_REACT` | Frontend is React (CRA/Vite) | Dockerfile.node, Dockerfile.fullstack |
| `FRAMEWORK_VUE` | Frontend is Vue (Vite) | Dockerfile.node, Dockerfile.fullstack |
| `FRAMEWORK_EXPRESS` | Backend/frontend is Express | Dockerfile.node |
| `FRAMEWORK_FLASK` | Backend is Flask | Dockerfile.python |
| `FRAMEWORK_DJANGO` | Backend is Django | Dockerfile.python |
| `FRAMEWORK_FASTAPI` | Backend is FastAPI | Dockerfile.python |
| `FRAMEWORK_PYTHON_GENERIC` | Backend is generic Python | Dockerfile.python |
| `PM_NPM` | Package manager is npm | Docker templates |
| `PM_YARN` | Package manager is yarn | Docker templates |
| `PM_PNPM` | Package manager is pnpm | Docker templates |
| `PM_PIP` | Package manager is pip | Docker templates |
| `PM_PIPENV` | Package manager is pipenv | Docker templates |
| `PM_POETRY` | Package manager is poetry | Docker templates |

##### User-Provided Variables

| Variable | Prompt | Default |
|---|---|---|
| `SERVER_HOST` | Server IP/hostname | — (required) |
| `SERVER_PORT` | SSH port | `22` |
| `SERVER_USER` | SSH username | — (required) |
| `NGINX_DOMAIN` | Domain name(s), space-separated | empty (skip Nginx) |
| `NGINX_SITE_NAME` | Nginx config filename | `PROJECT_NAME` |
| `NGINX_SSL_CERT` | SSL certificate path | Auto-detected on server |
| `NGINX_SSL_KEY` | SSL key path | Auto-detected on server |
| `NGINX_SSL_EXTRA` | Additional SSL directives | Auto-detected (Let's Encrypt) |
| `WATCHDOG_INTERVAL` | Health check interval (seconds) | `60` |
| `WATCHDOG_FAIL_THRESHOLD` | Failures before restart | `5` |
| `LOG_DIR` | Log directory relative to project root | `logs` |
| `LOG_MAX_SIZE` | Max log file size before rotation | `50M` |
| `LOG_ROTATE_COUNT` | Rotated log files to keep | `7` |
| `DEPLOY_MODE` | Deployment mode | `systemd` |
| `PROJECT_STRUCTURE` | `separated` or `monolith` | Auto-detected |

##### Computed Variables

| Variable | Computation |
|---|---|
| `PATH_DIRS` | `dirname(NODE_BIN):dirname(VENV_PYTHON):$USER_LOGIN_PATH` |
| `USER_DATA_DIR` | `/home/$RUN_USER/.$PROJECT_NAME-data` |
| `DEPLOY_TIMESTAMP` | ISO 8601 timestamp at render time |
| `BACKUP_DIR` | `$PROJECT_DIR/.deploy-backups/$DEPLOY_TIMESTAMP` |

#### Step 3: Determine Template Subset

Based on ProjectProfile and user choices, determine which templates to render:

```
IF deploy_mode == "systemd":
  ALWAYS render:
    - templates/ops/config.env.tpl
    - templates/ops/install.sh.tpl
    - templates/ops/install-deps.sh.tpl
    - templates/ops/uninstall.sh.tpl
    - templates/ops/status.sh.tpl
    - templates/ops/logs.sh.tpl
    - templates/ops/healthcheck.sh.tpl
    - templates/ops/deploy.sh.tpl
    - templates/systemd/watchdog.service.tpl
    - templates/systemd/watchdog.timer.tpl
    - templates/systemd/logrotate.tpl

  IF HAS_BACKEND:
    - templates/systemd/backend.service.tpl

  IF HAS_FRONTEND:
    - templates/systemd/frontend.service.tpl

  IF NGINX_DOMAIN is non-empty AND HAS_SSL:
    - templates/nginx/site-https.tpl

  IF NGINX_DOMAIN is non-empty AND NOT HAS_SSL:
    - templates/nginx/site-http.tpl

IF deploy_mode == "docker":
  ALWAYS render:
    - templates/ops/config.env.tpl
    - templates/ops/deploy.sh.tpl
    - templates/docker/docker-compose.tpl

  IF HAS_BACKEND AND HAS_FRONTEND:
    - templates/docker/Dockerfile.fullstack.tpl (OR separate Dockerfiles)

  IF HAS_BACKEND AND NOT HAS_FRONTEND:
    IF BACKEND_FRAMEWORK in (flask, django, fastapi, python_generic):
      - templates/docker/Dockerfile.python.tpl
    ELSE:
      - templates/docker/Dockerfile.node.tpl

  IF HAS_FRONTEND AND NOT HAS_BACKEND:
    - templates/docker/Dockerfile.node.tpl
```

#### Step 4: Resolve All Variables

Before rendering, build the complete variable map by merging sources in priority order:

1. **User overrides** (highest priority) — values explicitly provided via AskUserQuestion
2. **Auto-detected** — values from ProjectProfile (Phase 2)
3. **Server-resolved** — values detected on the target server via SSH (NODE_BIN, VENV_PYTHON, PATH_DIRS)
4. **Defaults** (lowest priority) — hardcoded sensible defaults from the registry above

Set all boolean feature flags based on the resolved values:
```
HAS_FRONTEND = FRONTEND_FRAMEWORK != "none" AND FRONTEND_FRAMEWORK != ""
HAS_BACKEND = BACKEND_FRAMEWORK != "none" AND BACKEND_FRAMEWORK != ""
HAS_NODE = HAS_FRONTEND OR BACKEND_FRAMEWORK in ("express", "nestjs", "fastify", "koa")
HAS_PYTHON = BACKEND_FRAMEWORK in ("flask", "django", "fastapi", "python_generic")
HAS_SSL = NGINX_SSL_CERT != "" AND NGINX_SSL_KEY != ""
FRAMEWORK_NEXTJS = FRONTEND_FRAMEWORK == "nextjs"
FRAMEWORK_NUXTJS = FRONTEND_FRAMEWORK == "nuxtjs"
... (set each FRAMEWORK_* and PM_* flag accordingly)
```

#### Step 5: Render Templates

For each template file selected in Step 3, perform rendering in this exact order:

1. **Read** the `.tpl` file content using `Read` tool
2. **Process conditional blocks**: Evaluate each `{{IF CONDITION}}` / `{{ENDIF CONDITION}}` pair:
   - If CONDITION is truthy: remove the `# {{IF CONDITION}}` and `# {{ENDIF CONDITION}}` marker lines, keep the content between them
   - If CONDITION is falsy: remove the marker lines AND all content between them
   - Process `{{IF_NOT CONDITION}}` / `{{ENDIF_NOT CONDITION}}` with inverted logic
   - Process nested conditionals inside-out
3. **Substitute variables**: Replace every `{{VARIABLE_NAME}}` with its resolved value from the variable map
4. **Validate**: Scan the rendered output for any remaining `{{...}}` patterns. If found, STOP and report which variables are unresolved. Do NOT write a file with unresolved placeholders.
5. **Write** the output file:
   - ops scripts: `ops/{filename}` (strip `.tpl` extension)
   - systemd templates: `ops/templates/{PROJECT_NAME}-{name}` (strip `.tpl`, prefix with project name)
   - nginx templates: `ops/templates/{PROJECT_NAME}-nginx` or `{PROJECT_NAME}-nginx-http`
   - Docker templates: project root (`Dockerfile`, `docker-compose.yml`)
6. **Set permissions**: For `.sh` files, note that `chmod +x` must be applied after upload to server

#### Step 6: Output File Mapping

After rendering, the generated `ops/` directory will have this structure:

```
ops/
├── config.env                          # from config.env.tpl
├── install.sh                          # from install.sh.tpl
├── install-deps.sh                     # from install-deps.sh.tpl
├── uninstall.sh                        # from uninstall.sh.tpl
├── status.sh                           # from status.sh.tpl
├── logs.sh                             # from logs.sh.tpl
├── healthcheck.sh                      # from healthcheck.sh.tpl
├── deploy.sh                           # from deploy.sh.tpl
└── templates/
    ├── {PROJECT_NAME}-backend.service  # from backend.service.tpl (if HAS_BACKEND)
    ├── {PROJECT_NAME}-frontend.service # from frontend.service.tpl (if HAS_FRONTEND)
    ├── {PROJECT_NAME}-watchdog.service # from watchdog.service.tpl
    ├── {PROJECT_NAME}-watchdog.timer   # from watchdog.timer.tpl
    ├── {PROJECT_NAME}-logrotate        # from logrotate.tpl
    ├── {PROJECT_NAME}-nginx            # from site-https.tpl (if SSL)
    └── {PROJECT_NAME}-nginx-http       # from site-http.tpl (if no SSL)
```

For Docker mode, additional files at project root:
```
Dockerfile                              # from Dockerfile.*.tpl
docker-compose.yml                      # from docker-compose.tpl
```

#### Step 7: Post-Render Validation

After all files are written, perform these validation checks:

1. **No unresolved placeholders**: `Grep` all rendered files for `{{` patterns — must return zero matches
2. **Shell syntax check**: For each `.sh` file, the SKILL notes that `bash -n <file>` should pass when run on the server. Record this as a verification step for Phase 6 (deployment).
3. **systemd unit structure**: Verify each `.service` file contains `[Unit]`, `[Service]`, `[Install]` sections
4. **Nginx config structure**: Verify nginx templates contain `server {` blocks with `listen` and `server_name` directives
5. **File count**: Verify the expected number of files were rendered (from Step 3 selection)

Report the validation results to the user before proceeding to deployment.
