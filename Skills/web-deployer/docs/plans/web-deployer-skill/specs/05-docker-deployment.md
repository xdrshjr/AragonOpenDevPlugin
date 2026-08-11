# Spec 05: Docker Deployment Pipeline

## Purpose

Define the Docker-based deployment pipeline: Dockerfile/Compose generation (when missing), image building, container orchestration, and service management via Docker Compose.

## Prerequisites

- Server has Docker and Docker Compose (checked in pre-flight)
- SSH connection established
- ProjectProfile available

## Smart Detection

```
if project has Dockerfile AND docker-compose.yml:
    mode = "use_existing"
elif project has Dockerfile only:
    mode = "use_dockerfile_generate_compose"
elif project has docker-compose.yml only:
    mode = "use_compose"  # unusual but possible
else:
    mode = "generate_all"
```

## Dockerfile Generation

### Node.js Frontend (Dockerfile.node.tpl)

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production=false
COPY . .
RUN {{BUILD_COMMAND}}

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT={{FRONTEND_PORT}}
COPY --from=builder /app/{{BUILD_OUTPUT}} ./{{BUILD_OUTPUT}}
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
{{IF NEXTJS_STANDALONE}}
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
{{ENDIF NEXTJS_STANDALONE}}
EXPOSE {{FRONTEND_PORT}}
CMD [{{FRONTEND_START_CMD}}]
```

### Python Backend (Dockerfile.python.tpl)

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PORT={{BACKEND_PORT}}
EXPOSE {{BACKEND_PORT}}
CMD [{{BACKEND_START_CMD}}]
```

### Fullstack (Dockerfile.fullstack.tpl)

Multi-stage build combining frontend build and backend:

```dockerfile
# Stage 1: Build frontend
FROM node:20-alpine AS frontend-builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN {{BUILD_COMMAND}}

# Stage 2: Backend + built frontend
FROM python:3.11-slim
WORKDIR /app
COPY backend/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ ./backend/
COPY --from=frontend-builder /app/{{BUILD_OUTPUT}} ./{{BUILD_OUTPUT}}
ENV PORT={{BACKEND_PORT}}
EXPOSE {{BACKEND_PORT}}
CMD [{{BACKEND_START_CMD}}]
```

## Docker Compose Generation (docker-compose.tpl)

```yaml
version: "3.8"

services:
  {{IF BACKEND_DETECTED}}
  backend:
    build:
      context: .
      dockerfile: {{BACKEND_DOCKERFILE}}
    ports:
      - "{{BACKEND_PORT}}:{{BACKEND_PORT}}"
    environment:
      - NODE_ENV=production
      - PORT={{BACKEND_PORT}}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:{{BACKEND_PORT}}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    volumes:
      - app-data:/app/data
  {{ENDIF BACKEND_DETECTED}}

  {{IF FRONTEND_DETECTED}}
  frontend:
    build:
      context: .
      dockerfile: {{FRONTEND_DOCKERFILE}}
    ports:
      - "{{FRONTEND_PORT}}:{{FRONTEND_PORT}}"
    environment:
      - NODE_ENV=production
      - PORT={{FRONTEND_PORT}}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:{{FRONTEND_PORT}}/"]
      interval: 30s
      timeout: 10s
      retries: 3
    {{IF BACKEND_DETECTED}}
    depends_on:
      backend:
        condition: service_healthy
    {{ENDIF BACKEND_DETECTED}}
  {{ENDIF FRONTEND_DETECTED}}

volumes:
  app-data:
```

## Deployment Steps

### Step 1: Upload Project Files

Upload project source to server via SFTP (excluding `node_modules/`, `.venv/`, `.git/`).

### Step 2: Generate Docker Files (if needed)

If `mode = "generate_all"` or `"use_dockerfile_generate_compose"`:
- Render appropriate Dockerfile template
- Render docker-compose.yml template
- Upload to server

### Step 3: Build Images

```bash
cd {{PROJECT_DIR}}
docker compose build --no-cache
```

### Step 4: Stop Existing Containers

```bash
docker compose down 2>/dev/null || true
```

### Step 5: Start Containers

```bash
docker compose up -d
```

### Step 6: Verify

```bash
# Wait for containers to be healthy
docker compose ps
# Check health endpoints
curl -sf http://localhost:{{BACKEND_PORT}}/health
curl -sf http://localhost:{{FRONTEND_PORT}}/
```

## Docker Ops Scripts

When Docker mode is used, generate Docker-specific ops scripts:

| Script | Purpose |
|--------|---------|
| `ops/docker-deploy.sh` | `docker compose build && docker compose up -d` |
| `ops/docker-status.sh` | `docker compose ps` + health checks |
| `ops/docker-logs.sh` | `docker compose logs -f [service]` |
| `ops/docker-stop.sh` | `docker compose down` |

These complement (don't replace) the standard ops scripts.

## .dockerignore Generation

Auto-generate `.dockerignore` if not present:

```
node_modules/
.venv/
venv/
.git/
.env
*.log
ops/
docs/
.deploy-backups/
```

## Coexistence with systemd

If a project was previously deployed via systemd and is now switching to Docker:
1. Stop and disable systemd services first
2. Warn user about the mode switch
3. Keep systemd ops scripts as backup (rename to `ops/systemd-backup/`)
