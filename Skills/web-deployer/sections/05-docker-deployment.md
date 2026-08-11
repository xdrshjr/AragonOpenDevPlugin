<!-- Section: Docker Deployment Pipeline -->
<!-- Author: dev-05 -->
<!-- Integrates into: SKILL.md Phase 6 (Docker path) -->
<!-- Consumed by: dev-07 (verification), dev-08 (integrator) -->

### Phase 6B: Docker Deployment Execution

Execute the Docker deployment pipeline on each target server. This phase is the alternative to Phase 6A (systemd) — only one of the two is executed per deployment. All remote commands use the SSH helpers from Phase 3.

> **Prerequisite check**: Before executing any step, confirm:
> - SSH connection to the target server is alive (`ensure_connected()`)
> - Docker and Docker Compose are available on the server (detected in pre-flight)
> - `ops/` directory has been uploaded to `{{PROJECT_DIR}}/ops/` on the server

#### Step 1: Smart Detection — Determine Docker Mode

Determine how much Docker configuration needs to be generated. Execute via `ssh_exec`:

```bash
cd "{{PROJECT_DIR}}"
HAS_DOCKERFILE=false
HAS_COMPOSE=false
COMPOSE_FILE=""

[ -f Dockerfile ] && HAS_DOCKERFILE=true
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -f "$f" ] && HAS_COMPOSE=true && COMPOSE_FILE="$f" && break
done

echo "HAS_DOCKERFILE=$HAS_DOCKERFILE"
echo "HAS_COMPOSE=$HAS_COMPOSE"
echo "COMPOSE_FILE=$COMPOSE_FILE"
```

Apply the mode decision matrix:

| Has Dockerfile | Has Compose | Mode | Action |
|---|---|---|---|
| yes | yes | `use_existing` | Use both as-is, no generation needed |
| yes | no | `use_dockerfile_generate_compose` | Generate docker-compose.yml from template |
| no | yes | `use_compose` | Use compose as-is (unusual but valid) |
| no | no | `generate_all` | Generate both Dockerfile and docker-compose.yml |

#### Step 2: Pre-Deployment Backup (Docker)

Create a backup of the current Docker state:

```bash
BACKUP_DIR="{{PROJECT_DIR}}/.deploy-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup docker compose state
cd "{{PROJECT_DIR}}"
docker compose ps --format json > "$BACKUP_DIR/container-state.json" 2>/dev/null || true
cp docker-compose.yml "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.yaml "$BACKUP_DIR/" 2>/dev/null || true
cp compose.yml "$BACKUP_DIR/" 2>/dev/null || true
cp Dockerfile* "$BACKUP_DIR/" 2>/dev/null || true
cp .dockerignore "$BACKUP_DIR/" 2>/dev/null || true

# Backup Nginx config (if exists)
cp "/etc/nginx/sites-available/{{NGINX_SITE_NAME}}" "$BACKUP_DIR/" 2>/dev/null || true

echo "$(date -Iseconds)" > "$BACKUP_DIR/backup.timestamp"

# Cleanup old backups — keep last 5
ls -dt "{{PROJECT_DIR}}/.deploy-backups"/*/ 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true

echo "Backup created: $BACKUP_DIR"
```

#### Step 3: Upload Project Files

Upload the project source code to the server via SFTP. Exclude large or unnecessary directories to minimize transfer time.

Use the `sftp_upload` helper from Phase 3 with an exclusion list:

```python
exclude_patterns = [
    "node_modules/",
    ".venv/",
    "venv/",
    ".git/",
    ".deploy-backups/",
    "__pycache__/",
    "*.pyc",
    ".next/",
    ".nuxt/",
    "dist/",
    "build/",
    "out/",
]

sftp_upload(
    ssh=ssh,
    local_path=project_dir,
    remote_path=server_context["remote_dir"],
    exclude=exclude_patterns,
)
```

**Note:** If the project was previously deployed via `git clone` on the server, prefer `git pull` over full SFTP upload. Check for `.git/` on the server:

```bash
cd "{{PROJECT_DIR}}" && [ -d .git ] && echo "GIT_REPO=true" || echo "GIT_REPO=false"
```

If `GIT_REPO=true`, use git pull instead:

```bash
cd "{{PROJECT_DIR}}" && git pull origin "$(git rev-parse --abbrev-ref HEAD)"
```

#### Step 4: Generate Docker Files (If Needed)

**If mode is `generate_all` or `use_dockerfile_generate_compose`:**

Select the appropriate Dockerfile template based on project type:

| Project Type | Template | Selection Logic |
|---|---|---|
| backend_only (Python) | `Dockerfile.python.tpl` | Python runtime detected, no frontend |
| frontend_only (Node.js) | `Dockerfile.node.tpl` | Node.js frontend detected, no backend |
| fullstack | `Dockerfile.fullstack.tpl` | Both frontend and backend detected |
| monolith (Next.js/Nuxt.js) | `Dockerfile.node.tpl` | Single full-stack JS framework |

Render the selected template(s) with the project variables and upload to the server.

**If mode is `generate_all` or `use_dockerfile_generate_compose`:**

Render `docker-compose.tpl` with conditional blocks resolved based on the ProjectProfile. Upload to `{{PROJECT_DIR}}/docker-compose.yml`.

#### Step 5: Generate .dockerignore (If Needed)

If `.dockerignore` does not exist in the project, generate one:

```bash
cd "{{PROJECT_DIR}}"
if [ ! -f .dockerignore ]; then
    cat > .dockerignore << 'DOCKERIGNORE'
node_modules/
.venv/
venv/
.git/
.env
.env.local
*.log
ops/
docs/
.deploy-backups/
__pycache__/
*.pyc
.next/
.nuxt/
dist/
build/
out/
.dockerignore
Dockerfile*
docker-compose*
DOCKERIGNORE
    echo ".dockerignore created"
fi
```

#### Step 6: Handle systemd-to-Docker Migration

If the project was previously deployed via systemd and is now switching to Docker, clean up systemd services first:

```bash
# Check for existing systemd services
if systemctl list-unit-files "{{PROJECT_NAME}}-*" 2>/dev/null | grep -q "{{PROJECT_NAME}}"; then
    echo "Existing systemd services detected — stopping before Docker deployment"
    systemctl stop "{{PROJECT_NAME}}-watchdog.timer"     2>/dev/null || true
    systemctl stop "{{PROJECT_NAME}}-watchdog.service"   2>/dev/null || true
    systemctl stop "{{PROJECT_NAME}}-frontend.service"   2>/dev/null || true
    systemctl stop "{{PROJECT_NAME}}-backend.service"    2>/dev/null || true
    systemctl disable "{{PROJECT_NAME}}-watchdog.timer"     2>/dev/null || true
    systemctl disable "{{PROJECT_NAME}}-frontend.service"   2>/dev/null || true
    systemctl disable "{{PROJECT_NAME}}-backend.service"    2>/dev/null || true

    # Move systemd unit files to backup, don't delete
    mkdir -p "{{PROJECT_DIR}}/ops/systemd-backup/"
    mv /etc/systemd/system/{{PROJECT_NAME}}-*.service "{{PROJECT_DIR}}/ops/systemd-backup/" 2>/dev/null || true
    mv /etc/systemd/system/{{PROJECT_NAME}}-*.timer "{{PROJECT_DIR}}/ops/systemd-backup/" 2>/dev/null || true
    systemctl daemon-reload

    echo "systemd services stopped and backed up to ops/systemd-backup/"
fi
```

#### Step 7: Stop Existing Containers

Stop any running containers for this project:

```bash
cd "{{PROJECT_DIR}}"

# Detect docker compose command variant
if docker compose version > /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif docker-compose version > /dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    echo "ERROR: Neither 'docker compose' nor 'docker-compose' found"
    exit 1
fi

$COMPOSE_CMD down 2>/dev/null || true
echo "Existing containers stopped"
```

#### Step 8: Build Docker Images

Build the Docker images on the server. Use `ssh_exec_long` — this can take several minutes for large projects.

```bash
cd "{{PROJECT_DIR}}"
$COMPOSE_CMD build --no-cache 2>&1
```

**Error handling:** If the build fails, capture the error output and present to the user:

```
AskUserQuestion:
  question: "Docker build failed on {{SERVER_HOST}}. Error:\n{{stderr_last_30_lines}}\n\nWhat would you like to do?"
  candidates:
    - "Retry the build"
    - "Retry with cache (docker compose build)"
    - "Connect me to the server for manual debugging"
    - "Abort deployment for this server"
```

If "Retry with cache", run `$COMPOSE_CMD build` (without `--no-cache`).

#### Step 9: Start Containers

```bash
cd "{{PROJECT_DIR}}"
$COMPOSE_CMD up -d
echo "Containers started"
```

#### Step 10: Wait for Container Health

Wait for all containers to become healthy. Docker Compose health checks are defined in the compose file (from the template).

```bash
cd "{{PROJECT_DIR}}"

# Wait up to 90 seconds for all services to be healthy
MAX_WAIT=90
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    ALL_HEALTHY=true

    # Check each running container
    for container_id in $($COMPOSE_CMD ps -q 2>/dev/null); do
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")
        state=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")

        if [ "$state" != "running" ]; then
            echo "Container $container_id is $state (not running)"
            ALL_HEALTHY=false
            break
        fi

        if [ "$health" = "unhealthy" ]; then
            echo "Container $container_id is unhealthy"
            ALL_HEALTHY=false
            break
        fi

        if [ "$health" = "starting" ]; then
            ALL_HEALTHY=false
        fi
    done

    if [ "$ALL_HEALTHY" = "true" ]; then
        echo "All containers healthy after ${ELAPSED}s"
        break
    fi

    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "WARNING: Not all containers healthy after ${MAX_WAIT}s"
    $COMPOSE_CMD ps
fi
```

Also verify HTTP health endpoints directly:

```bash
{{IF HAS_BACKEND}}
curl -sf --max-time 5 "http://localhost:{{BACKEND_PORT}}/health" && echo "Backend: healthy" || echo "Backend: NOT responding"
{{ENDIF HAS_BACKEND}}

{{IF HAS_FRONTEND}}
curl -sf --max-time 5 "http://localhost:{{FRONTEND_PORT}}/" && echo "Frontend: healthy" || echo "Frontend: NOT responding"
{{ENDIF HAS_FRONTEND}}
```

#### Step 11: Generate Docker-Specific Ops Scripts

In addition to the standard ops scripts, generate Docker-specific convenience scripts in the `ops/` directory:

**ops/docker-deploy.sh:**

```bash
#!/bin/bash
# One-command Docker redeploy
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"

cd "$PROJECT_DIR"

echo "=== Pulling latest code ==="
git pull origin "$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null || echo "Not a git repo, skipping pull"

echo "=== Building images ==="
docker compose build

echo "=== Restarting containers ==="
docker compose down
docker compose up -d

echo "=== Waiting for health ==="
sleep 10
docker compose ps
echo "Deploy complete"
```

**ops/docker-status.sh:**

```bash
#!/bin/bash
# Docker container status
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
cd "$PROJECT_DIR"
docker compose ps
echo ""
echo "=== Health Checks ==="
for port in $BACKEND_PORT $FRONTEND_PORT; do
    [ -z "$port" ] && continue
    if curl -sf --max-time 3 "http://localhost:$port/" > /dev/null 2>&1; then
        echo "  Port $port: OK"
    else
        echo "  Port $port: NOT responding"
    fi
done
```

**ops/docker-logs.sh:**

```bash
#!/bin/bash
# Docker container logs
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
cd "$PROJECT_DIR"
SERVICE="${1:-}"
FOLLOW="${2:-}"
if [ -n "$SERVICE" ]; then
    docker compose logs $FOLLOW "$SERVICE"
else
    docker compose logs $FOLLOW
fi
```

**ops/docker-stop.sh:**

```bash
#!/bin/bash
# Stop Docker containers
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
cd "$PROJECT_DIR"
docker compose down
echo "All containers stopped"
```

Upload these scripts to the server and set executable permissions:

```bash
chmod +x "{{PROJECT_DIR}}/ops/docker-deploy.sh"
chmod +x "{{PROJECT_DIR}}/ops/docker-status.sh"
chmod +x "{{PROJECT_DIR}}/ops/docker-logs.sh"
chmod +x "{{PROJECT_DIR}}/ops/docker-stop.sh"
```

#### Step 12: Quick Status Check

After containers are started, display the final status:

```bash
cd "{{PROJECT_DIR}}"
echo "=== Docker Container Status ==="
docker compose ps

echo ""
echo "=== Container Resource Usage ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker compose ps -q) 2>/dev/null || true
```

---

**Phase 6B output gate:** All expected containers must be in `running` state with health status `healthy` (or `none` if no health check defined). If any container is in `exited` or `restarting` state, proceed to Phase 7 for verification and failure handling.
