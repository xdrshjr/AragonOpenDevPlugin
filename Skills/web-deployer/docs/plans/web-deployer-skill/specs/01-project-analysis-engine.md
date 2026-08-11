# Spec 01: Project Analysis Engine

## Purpose

Scan the user's current working directory to auto-detect project type, structure, technology stack, and deployment requirements. Produce a structured `ProjectProfile` that all downstream phases consume.

## Inputs

- Current working directory path
- User overrides (optional, via interactive prompts)

## Outputs

A `ProjectProfile` object containing:

```
ProjectProfile:
  project_name: string          # kebab-case, from package.json name or directory name
  project_dir: string           # absolute path
  project_type: enum            # "fullstack" | "frontend_only" | "backend_only" | "monolith"

  frontend:
    detected: boolean
    framework: string           # "nextjs" | "react" | "vue" | "angular" | "static" | "none"
    entry_point: string         # e.g., "server.js", "npm start", etc.
    build_command: string       # e.g., "npm run build"
    build_output: string        # e.g., "out/", "dist/", ".next/"
    port: number                # default 3000
    package_manager: string     # "npm" | "yarn" | "pnpm"

  backend:
    detected: boolean
    framework: string           # "flask" | "django" | "express" | "fastapi" | "nestjs" | "none"
    entry_point: string         # e.g., "app.py", "manage.py runserver", "server.js"
    runtime: string             # "python" | "node"
    venv_path: string           # e.g., "backend/.venv" or ".venv"
    requirements_file: string   # e.g., "requirements.txt", "Pipfile"
    port: number                # default 5000

  docker:
    has_dockerfile: boolean
    has_compose: boolean
    dockerfile_path: string
    compose_path: string

  deployment:
    has_ops: boolean            # existing ops/ directory
    has_existing_services: boolean
    recommended_mode: string    # "systemd" | "docker"
```

## Detection Logic

### Step 1: Scan Root Directory

Use `Glob` and `Read` to find key markers:

| File Pattern | What It Indicates |
|-------------|-------------------|
| `package.json` | Node.js project present |
| `requirements.txt` / `Pipfile` / `pyproject.toml` | Python project present |
| `next.config.*` | Next.js framework |
| `nuxt.config.*` | Nuxt.js framework |
| `vue.config.*` / `vite.config.*` (with vue) | Vue framework |
| `angular.json` | Angular framework |
| `app.py` / `wsgi.py` | Flask backend |
| `manage.py` | Django backend |
| `Dockerfile` | Docker-ready |
| `docker-compose.yml` / `docker-compose.yaml` / `compose.yml` | Docker Compose ready |
| `ops/` directory | Existing ops toolkit |

### Step 2: Read package.json

If `package.json` exists, extract:
- `name` → project_name candidate
- `scripts.build` → build_command
- `scripts.start` → entry_point candidate
- `dependencies` → framework detection (next, react, vue, express, etc.)
- `scripts.dev` → dev server info

### Step 3: Detect Backend

If Python markers found:
- Check `backend/` subdirectory first (separated project), then root
- Look for `app.py` → Flask, `manage.py` → Django, `main.py` with FastAPI import → FastAPI
- Detect venv: `backend/.venv/`, `.venv/`, `venv/`
- Read `requirements.txt` for framework confirmation

If Node.js backend (no Python markers but server-side patterns):
- `server.js`, `index.js` with express/koa/fastify imports
- `src/main.ts` with NestJS patterns

### Step 4: Classify Project Type

```
if frontend.detected AND backend.detected:
    project_type = "fullstack"
elif frontend.detected:
    project_type = "frontend_only"
elif backend.detected:
    project_type = "backend_only"
else:
    project_type = "monolith"  # fallback, ask user
```

### Step 5: Infer Defaults

| Field | Default | Source |
|-------|---------|--------|
| project_name | directory name (kebab-case) | `package.json`.name or `basename(cwd)` |
| frontend.port | 3000 | convention |
| backend.port | 5000 (Flask/FastAPI), 8000 (Django), 3001 (Express) | framework convention |
| build_command | `npm run build` | `package.json`.scripts.build |
| recommended_mode | "docker" if Docker files exist, "systemd" otherwise | detection |

### Step 6: User Confirmation

Present the detected profile to the user via `AskUserQuestion`:
- Show all detected values
- Allow override of any field
- Confirm project_name (used for systemd service naming and ops script prefixes)

## Edge Cases

- **Monorepo**: Multiple `package.json` files → detect workspace root, present choices
- **No markers found**: Ask user to describe project structure
- **Conflicting markers**: e.g., both Flask and Django → ask user which is primary
- **Custom frameworks**: Fall back to generic "python" or "node" backend type
