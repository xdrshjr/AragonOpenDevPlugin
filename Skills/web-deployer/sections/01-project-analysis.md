### Phase 2: Project Analysis

Scan the current working directory to auto-detect project type, technology stack, structure, and deployment requirements. Produce a `ProjectProfile` data structure that all downstream phases consume (template rendering, ops generation, deployment execution, verification).

#### Step 1: Marker File Discovery

Use `Glob` to scan the project root for detection markers. Run all glob patterns in parallel to minimize latency.

```
Glob: package.json
Glob: requirements.txt
Glob: Pipfile
Glob: pyproject.toml
Glob: next.config.*
Glob: nuxt.config.*
Glob: vue.config.*
Glob: vite.config.*
Glob: angular.json
Glob: app.py
Glob: wsgi.py
Glob: manage.py
Glob: main.py
Glob: server.js
Glob: server.ts
Glob: index.js
Glob: index.ts
Glob: Dockerfile
Glob: docker-compose.yml
Glob: docker-compose.yaml
Glob: compose.yml
Glob: compose.yaml
Glob: ops/config.env
Glob: environment.yml
Glob: environment.yaml
Glob: backend/environment.yml
Glob: backend/
Glob: frontend/
Glob: */package.json
```

Record which markers exist. Store results in a mental checklist — each marker maps to a detection signal per the table below.

#### Step 2: Detection Marker Table

Use the following mapping to classify detected markers. A marker is "present" if the corresponding Glob returned a match.

| Marker File | Signal | Category |
|---|---|---|
| `package.json` | Node.js project present | runtime |
| `requirements.txt` / `Pipfile` / `pyproject.toml` | Python project present | runtime |
| `next.config.js` / `next.config.mjs` / `next.config.ts` | Next.js framework | frontend_framework |
| `nuxt.config.js` / `nuxt.config.ts` | Nuxt.js framework | frontend_framework |
| `vue.config.js` OR `vite.config.*` with Vue dependency | Vue framework | frontend_framework |
| `angular.json` | Angular framework | frontend_framework |
| `app.py` / `wsgi.py` (in root or `backend/`) | Flask backend | backend_framework |
| `manage.py` (in root or `backend/`) | Django backend | backend_framework |
| `main.py` with FastAPI/uvicorn import | FastAPI backend | backend_framework |
| `server.js` / `server.ts` with express import | Express backend | backend_framework |
| `src/main.ts` with NestJS import | NestJS backend | backend_framework |
| `Dockerfile` | Docker-ready | docker |
| `docker-compose.yml` / `docker-compose.yaml` / `compose.yml` / `compose.yaml` | Docker Compose ready | docker |
| `ops/` directory with `config.env` | Existing ops toolkit | ops |
| `environment.yml` / `environment.yaml` | Conda environment | runtime |
| `backend/` subdirectory | Separated backend structure | structure |
| `frontend/` subdirectory | Separated frontend structure | structure |

#### Step 3: Parse package.json

If `package.json` exists, read it with the `Read` tool and extract:

```
Read: package.json
```

Extract these fields:

| Field | Extracts To | Purpose |
|---|---|---|
| `name` | `project_name` candidate | Service naming, ops script prefix |
| `scripts.build` | `frontend.build_command` | Build step during deployment |
| `scripts.start` | `frontend.entry_point` candidate | How to start the frontend service |
| `scripts.dev` | (informational) | Confirm dev server framework |
| `dependencies.next` | Next.js detection | Framework classification |
| `dependencies.react` | React detection (if no Next.js) | Framework classification |
| `dependencies.vue` | Vue detection | Framework classification |
| `dependencies.@angular/core` | Angular detection | Framework classification |
| `dependencies.express` | Express backend detection | Backend classification |
| `dependencies.fastify` | Fastify backend detection | Backend classification |
| `dependencies.koa` | Koa backend detection | Backend classification |
| `devDependencies.next` | Next.js detection (alt) | Sometimes next is in devDeps |
| `devDependencies.@angular/cli` | Angular detection (alt) | Angular CLI in devDeps |

Also detect the package manager:
- If `yarn.lock` exists in project root -> `package_manager = "yarn"`
- If `pnpm-lock.yaml` exists in project root -> `package_manager = "pnpm"`
- Otherwise -> `package_manager = "npm"`

If a `backend/package.json` or `frontend/package.json` exists in a separated project structure, read those as well and extract the same fields scoped to their respective component.

#### Step 4: Backend Detection

Detect the backend framework using this ordered logic. Check `backend/` subdirectory first (indicates separated project), then fall back to root directory.

**Python backends:**

1. **Flask**: `app.py` or `wsgi.py` exists, AND (`requirements.txt` contains `flask` OR `Pipfile` contains `flask` OR `pyproject.toml` contains `flask`)
   - If `app.py` exists, read the first 30 lines to confirm Flask import: `from flask import` or `import flask`
   - Entry point: `app.py` (or `wsgi.py` if it exists)

2. **Django**: `manage.py` exists, AND (`requirements.txt` contains `django` OR `Pipfile` contains `django` OR `pyproject.toml` contains `django`)
   - Read `manage.py` first 10 lines to confirm Django: `django` in content
   - Entry point: `manage.py runserver` (dev) / `gunicorn` (prod)
   - Also check for `settings.py` or `<project>/settings.py` to extract `ALLOWED_HOSTS`, ports

3. **FastAPI**: `main.py` exists, AND (`requirements.txt` contains `fastapi` OR `uvicorn`)
   - Read `main.py` first 30 lines to confirm: `from fastapi import` or `import fastapi`
   - Entry point: `uvicorn main:app` (or whatever the app variable is named)

For all Python backends, detect the virtual environment:
```
Glob: backend/.venv/
Glob: .venv/
Glob: venv/
Glob: backend/venv/
```

Also check for conda environments:
- Look for `environment.yml` or `environment.yaml` in project root or `backend/` subdirectory
- If found, record `backend.venv_path = "conda"` and note the environment name from the `name:` field in the YAML file
- Conda environments are activated differently from venvs — downstream templates must use `conda activate <env_name>` instead of `source .venv/bin/activate`

Record the first match as `backend.venv_path`. Also record which requirements file was found (`requirements.txt`, `Pipfile`, `pyproject.toml`, or `environment.yml`) as `backend.requirements_file`.

**Node.js backends:**

4. **Express**: `server.js` or `server.ts` or `index.js` or `index.ts` exists with express dependency in `package.json`
   - Read the entry file first 30 lines to confirm: `require('express')` or `from 'express'` or `import express`
   - Entry point: the file that contains the express import

5. **NestJS**: `src/main.ts` exists AND `@nestjs/core` in `package.json` dependencies
   - Entry point: `dist/main.js` (compiled) or `npm run start:prod`

6. **Fastify/Koa**: Similar pattern — check `package.json` dependencies for `fastify` or `koa`, then confirm via file import scanning

If no backend framework is positively identified but Python or Node.js runtime markers exist, classify as generic `"python"` or `"node"` backend and flag for user confirmation.

#### Step 5: Frontend Detection

Detect the frontend framework using this ordered logic. Check `frontend/` subdirectory first (indicates separated project), then fall back to root directory.

1. **Next.js**: `next.config.js` or `next.config.mjs` or `next.config.ts` exists, OR `next` in `package.json` dependencies/devDependencies
   - Build command: `npm run build` (produces `.next/` or `out/` if static export)
   - Build output: `.next/` (SSR) or `out/` (static export — check if `next.config` has `output: 'export'`)
   - Port: 3000 (default)
   - Note: Next.js is a **full-stack** framework. If Next.js is detected AND no separate backend is found, classify project as `"monolith"` rather than `"frontend_only"`

2. **Nuxt.js**: `nuxt.config.js` or `nuxt.config.ts` exists, OR `nuxt` in `package.json` dependencies
   - Build command: `npm run build`
   - Build output: `.nuxt/` / `.output/`
   - Port: 3000 (default)
   - Note: Like Next.js, Nuxt is full-stack capable. Apply same monolith logic.

3. **Vue (Vite or Vue CLI)**: `vue` in `package.json` dependencies AND (`vite.config.*` exists OR `vue.config.js` exists)
   - If `vite.config.*` exists, read first 20 lines to confirm Vue plugin: `@vitejs/plugin-vue`
   - Build command: `npm run build`
   - Build output: `dist/`
   - Port: 5173 (Vite dev default) / 3000 (serve)

4. **React (Create React App or Vite)**: `react` in `package.json` dependencies AND NOT Next.js
   - If `vite.config.*` exists with `@vitejs/plugin-react` -> Vite + React
   - If `react-scripts` in dependencies -> Create React App
   - Build command: `npm run build`
   - Build output: `build/` (CRA) or `dist/` (Vite)
   - Port: 3000 (CRA) / 5173 (Vite)

5. **Angular**: `angular.json` exists OR `@angular/core` in `package.json` dependencies
   - Build command: `ng build` or `npm run build`
   - Build output: `dist/<project-name>/`
   - Port: 4200 (default dev)

6. **Static site**: If `index.html` exists at root and no framework detected -> static site
   - Build command: none
   - Build output: `.` (root)
   - Port: 80 or 3000 (served via Nginx directly)

If no frontend framework is positively identified but Node.js `package.json` exists with a `build` script, classify as generic `"node_frontend"` and flag for user confirmation.

#### Step 6: Docker Detection

Check for existing Docker configuration:

```
if Dockerfile exists:
    docker.has_dockerfile = true
    docker.dockerfile_path = path to Dockerfile
if docker-compose.yml OR docker-compose.yaml OR compose.yml OR compose.yaml exists:
    docker.has_compose = true
    docker.compose_path = path to compose file
```

If a Dockerfile exists, read it with `Read` and extract:
- Base image (FROM line) — confirms runtime (node, python, etc.)
- Exposed ports (EXPOSE line) — cross-validate with detected ports
- Entry point (CMD or ENTRYPOINT) — cross-validate with detected entry points

If a compose file exists, read it and extract:
- Service names — cross-validate with frontend/backend detection
- Port mappings — cross-validate with detected ports
- Volume mounts — useful for deployment planning
- Environment variables — may contain port overrides or config

#### Step 7: Project Type Classification

Apply this decision tree to classify the overall project type:

```
if frontend.detected AND backend.detected:
    if backend is in a separate subdirectory (backend/) OR frontend is in a separate subdirectory (frontend/):
        project_type = "fullstack"      # Separated frontend + backend
    else:
        project_type = "fullstack"      # Co-located frontend + backend
elif frontend.detected AND frontend.framework in ["nextjs", "nuxtjs"]:
    project_type = "monolith"           # Full-stack framework acting as both
elif frontend.detected:
    project_type = "frontend_only"      # Pure SPA or static site
elif backend.detected:
    project_type = "backend_only"       # API server only
else:
    project_type = "unknown"            # No markers found — will ask user
```

#### Step 8: Default Value Inference

For each detected component, infer default values that will populate template variables. These defaults are overridable by the user in Step 10.

**Project-level defaults:**

| Field | Default | Source |
|---|---|---|
| `project_name` | `package.json` `.name` field (kebab-case) if available, otherwise `basename` of current directory converted to kebab-case | Auto |
| `project_dir` | Absolute path of current working directory | Auto |
| `deployment.recommended_mode` | `"docker"` if Docker files exist, `"systemd"` otherwise | Detection |
| `deployment.has_ops` | `true` if `ops/config.env` found | Detection |
| `deployment.has_existing_services` | `true` if existing systemd unit files or running Docker containers are found for this project name (checked during server connection in Phase 3; default `false` during Phase 2) | Detection |

**Frontend defaults per framework:**

| Framework | Port | Build Command | Build Output | Entry Point |
|---|---|---|---|---|
| Next.js | 3000 | `npm run build` | `.next/` | `npm start` (or `node server.js` for custom server) |
| Nuxt.js | 3000 | `npm run build` | `.output/` | `node .output/server/index.mjs` |
| Vue (Vite) | 3000 | `npm run build` | `dist/` | Static files served by Nginx |
| Vue (CLI) | 3000 | `npm run build` | `dist/` | Static files served by Nginx |
| React (CRA) | 3000 | `npm run build` | `build/` | Static files served by Nginx |
| React (Vite) | 3000 | `npm run build` | `dist/` | Static files served by Nginx |
| Angular | 3000 | `npm run build` | `dist/<name>/` | Static files served by Nginx |
| Static | 80 | (none) | `.` | Static files served by Nginx |

Note: For static SPA frameworks (Vue, React non-SSR, Angular), the frontend port is used by the dev server only. In production, Nginx serves the static build output directly. The port field still matters for the dev/preview mode and for the Nginx upstream configuration if SSR is used.

Override the build command if `package.json` `scripts.build` contains a different value.

**Backend defaults per framework:**

| Framework | Port | Runtime | Entry Point | Production Command |
|---|---|---|---|---|
| Flask | 5000 | python | `app.py` | `gunicorn -w 4 -b 0.0.0.0:5000 app:app` |
| Django | 8000 | python | `manage.py` | `gunicorn -w 4 -b 0.0.0.0:8000 <project>.wsgi:application` |
| FastAPI | 8000 | python | `main.py` | `uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4` |
| Express | 3001 | node | `server.js` | `node server.js` (or `npm start`) |
| NestJS | 3001 | node | `dist/main.js` | `node dist/main.js` (or `npm run start:prod`) |
| Fastify | 3001 | node | `server.js` | `node server.js` (or `npm start`) |
| Koa | 3001 | node | `server.js` | `node server.js` (or `npm start`) |

Note: When both frontend and backend are detected, the backend port must differ from the frontend port. The defaults above already account for this (frontend=3000, backend=5000/8000/3001). If a port conflict is detected (e.g., user override sets both to 3000), flag it in the confirmation step.

#### Step 9: Assemble ProjectProfile

Combine all detection results into the `ProjectProfile` structure. This is the canonical data structure consumed by all downstream phases.

```
ProjectProfile:
  project_name: string          # kebab-case name for service naming and ops scripts
  project_dir: string           # absolute path to project root
  project_type: string          # "fullstack" | "frontend_only" | "backend_only" | "monolith" | "unknown"

  frontend:
    detected: boolean           # true if any frontend framework or static site found
    framework: string           # "nextjs" | "nuxtjs" | "react" | "vue" | "angular" | "static" | "none"
    entry_point: string         # how to start the frontend in production
    build_command: string       # command to build the frontend
    build_output: string        # directory containing build artifacts
    port: number                # port for the frontend service
    package_manager: string     # "npm" | "yarn" | "pnpm"
    subdirectory: string        # "frontend/" or "." if root-level

  backend:
    detected: boolean           # true if any backend framework found
    framework: string           # "flask" | "django" | "fastapi" | "express" | "nestjs" | "fastify" | "koa" | "none"
    entry_point: string         # main file or start command
    production_command: string  # full production run command (gunicorn, uvicorn, node, etc.)
    runtime: string             # "python" | "node"
    venv_path: string           # path to virtualenv (Python only), empty string if none
    requirements_file: string   # "requirements.txt" | "Pipfile" | "pyproject.toml" | "package.json"
    port: number                # port for the backend service
    subdirectory: string        # "backend/" or "." if root-level

  docker:
    has_dockerfile: boolean     # true if Dockerfile found
    has_compose: boolean        # true if docker-compose/compose file found
    dockerfile_path: string     # relative path to Dockerfile
    compose_path: string        # relative path to compose file

  deployment:
    has_ops: boolean            # true if existing ops/ directory found
    has_existing_services: boolean  # true if existing systemd services or Docker containers found for this project
    recommended_mode: string    # "systemd" | "docker"
```

This structure is passed conceptually to Phase 3 (server info collection), Phase 4 (deployment plan), Phase 5 (template rendering), Phase 6 (deployment execution), and Phase 7 (verification). The integrator (dev-08) will define how this data flows between phases in the final SKILL.md — for this section, the profile is held in memory as a structured set of detected values.

#### Step 10: Present ProjectProfile to User

Present the detected profile to the user via `AskUserQuestion` for confirmation and override. Format the presentation clearly so the user can verify each detected value.

**If the interaction language (from Phase 1) is English, present:**

```
I've analyzed your project. Here's what I detected:

=== Project Profile ===

Project Name:       {{project_name}}
Project Directory:  {{project_dir}}
Project Type:       {{project_type}}

--- Frontend ---
Detected:           {{frontend.detected}}
Framework:          {{frontend.framework}}
Build Command:      {{frontend.build_command}}
Build Output:       {{frontend.build_output}}
Entry Point:        {{frontend.entry_point}}
Port:               {{frontend.port}}
Package Manager:    {{frontend.package_manager}}
Subdirectory:       {{frontend.subdirectory}}

--- Backend ---
Detected:           {{backend.detected}}
Framework:          {{backend.framework}}
Runtime:            {{backend.runtime}}
Entry Point:        {{backend.entry_point}}
Prod Command:       {{backend.production_command}}
Virtual Env:        {{backend.venv_path}}
Requirements:       {{backend.requirements_file}}
Port:               {{backend.port}}
Subdirectory:       {{backend.subdirectory}}

--- Docker ---
Dockerfile:         {{docker.has_dockerfile}} {{docker.dockerfile_path}}
Docker Compose:     {{docker.has_compose}} {{docker.compose_path}}

--- Deployment ---
Existing ops/:      {{deployment.has_ops}}
Existing Services:  {{deployment.has_existing_services}}
Recommended Mode:   {{deployment.recommended_mode}}

A) Looks correct — proceed with these settings
B) I need to correct some values (please specify which fields and their correct values)
C) This is wrong — let me describe my project manually
```

**If the interaction language is Chinese, present the same information with Chinese labels** (e.g., "项目名称", "项目目录", "项目类型", "前端", "后端", "Docker", "部署").

Use `AskUserQuestion` with candidate answers A/B/C.

#### Step 11: User Confirmation and Override Flow

Handle the user's response:

**If user selects A (Confirm):**
- Lock the `ProjectProfile` and proceed to Phase 3.

**If user selects B (Correct specific values):**
- Parse the user's corrections. They may specify one or more fields to override.
- Apply each override to the `ProjectProfile`.
- Re-present ONLY the changed fields for final confirmation:

```
Updated values:
  - backend.port: 5000 → 8080
  - frontend.framework: react → nextjs

A) Confirmed — proceed
B) More corrections needed
```

- Loop until the user confirms with A. Maximum 3 correction rounds — after that, inform the user and proceed with current values.

**If user selects C (Manual description):**
- The auto-detection was insufficient. Ask the user to describe their project structure:

```
Please describe your project:
1. What is your frontend framework? (nextjs / react / vue / angular / nuxtjs / static / none)
2. What is your backend framework? (flask / django / fastapi / express / nestjs / none)
3. Is your project structure separated (frontend/ + backend/ subdirectories) or co-located?
4. What ports do your services use?
5. Do you have Docker configuration?
```

- Use `AskUserQuestion` with the above as the question body, free-form answer.
- Parse the user's response and manually populate the `ProjectProfile`.
- Present the manually-constructed profile for confirmation (same as Step 10).

#### Step 12: Edge Case Handling

Handle these edge cases during detection. Each edge case is resolved before the profile is presented to the user.

**Edge Case 1: Monorepo with multiple package.json files**

Detection: `Glob: */package.json` returns more than one result (excluding `node_modules`).

Resolution:
- Identify the workspace root: check for `workspaces` field in root `package.json`, or `pnpm-workspace.yaml`, or `lerna.json`.
- If workspace root found, list the workspace packages and ask the user which one to deploy:

```
I detected a monorepo with multiple packages:
  1. packages/web-app (Next.js)
  2. packages/api-server (Express)
  3. packages/shared (library)

Which package(s) should I deploy?
A) Deploy package 1 as frontend + package 2 as backend
B) Deploy only package 1
C) Deploy only package 2
D) Let me specify
```

- Use the selected package(s) as the effective project root for all subsequent detection.

**Edge Case 2: No markers found**

Detection: None of the marker files from the detection table were found.

Resolution:
- Check if the directory is empty or contains only non-web files.
- Inform the user and fall back to manual description (same as Step 11, option C):

```
I couldn't detect any known web project markers in this directory.
This might mean:
  - You're not in the project root directory
  - Your project uses an uncommon structure
  - This isn't a web project

Would you like to:
A) Describe your project manually
B) Change to a different directory and re-scan
C) Cancel deployment
```

**Edge Case 3: Conflicting markers**

Detection: Markers suggest multiple backend frameworks (e.g., both `app.py` with Flask imports AND `manage.py` with Django imports), or multiple frontend frameworks.

Resolution:
- Present the conflict to the user:

```
I detected conflicting signals:
  - Flask: app.py found with Flask import
  - Django: manage.py found with Django import

Which is the primary backend framework for this project?
A) Flask (app.py)
B) Django (manage.py)
C) Both are used (describe your setup)
```

- Apply the user's choice and discard the conflicting detection.

**Edge Case 4: Existing ops/ directory found**

Detection: `ops/config.env` exists in the project.

Resolution:
- Read the existing `config.env` to extract previously configured values (ports, domain, project name).
- Use these values as higher-priority defaults (they override framework-conventional defaults).
- Inform the user:

```
I found an existing ops/ directory with configuration. I'll use its values as defaults:
  - BACKEND_PORT=5000
  - FRONTEND_PORT=3000
  - NGINX_DOMAIN=example.com

These can still be overridden in the confirmation step.
```

**Edge Case 5: Next.js or Nuxt.js as monolith**

Detection: Next.js or Nuxt.js detected as frontend, but no separate backend detected.

Resolution:
- These are full-stack frameworks. If the project has API routes (`pages/api/` for Next.js or `server/api/` for Nuxt.js), classify as `"monolith"` rather than `"frontend_only"`.
- Check:
  ```
  Glob: pages/api/**/*
  Glob: app/api/**/*
  Glob: server/api/**/*
  ```
- If API routes found, set `project_type = "monolith"` and note that both frontend and API are served by the same process.

**Edge Case 6: Python project with no recognized framework**

Detection: `requirements.txt` or `pyproject.toml` exists, Python files exist, but no Flask/Django/FastAPI import found.

Resolution:
- Check for other WSGI/ASGI frameworks: `bottle`, `tornado`, `sanic`, `starlette`, `aiohttp`.
- If found, classify as that framework with generic Python backend defaults.
- If none found, classify as `backend.framework = "python_generic"` and ask user for entry point and run command.

**Edge Case 7: Port conflict between frontend and backend**

Detection: After applying defaults and user overrides, `frontend.port == backend.port`.

Resolution:
- Flag immediately during Step 10 presentation with a warning:

```
WARNING: Frontend port (3000) conflicts with backend port (3000).
These must be different for deployment to work.
Suggested fix: Change backend port to 5000.
```

- Auto-apply the suggested fix unless user provides a different override.

---

**Phase 2 output gate:** The `ProjectProfile` must be fully populated and user-confirmed before proceeding to Phase 3. Every field must have a value (detected, defaulted, or user-provided). The `project_type` must not be `"unknown"` — if detection failed and the user chose not to describe their project manually, halt the skill with a clear message.
