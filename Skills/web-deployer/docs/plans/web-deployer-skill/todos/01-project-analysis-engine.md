# TODO 01: Project Analysis Engine

**Spec Reference:** [specs/01-project-analysis-engine.md](../specs/01-project-analysis-engine.md)

## Dependencies

- `depends_on: []` — no dependencies, foundational module
- `blocks: [02, 04, 05, 08, 09]` — template system needs ProjectProfile; systemd/docker/ops/workflow need detection results
- `parallel_group: A`

## Tasks

- [x] Define project detection markers table in SKILL.md (package.json, requirements.txt, next.config, manage.py, Dockerfile, etc.)
- [x] Write project scanning logic: use Glob to find marker files in current directory
- [x] Write package.json parsing: extract name, scripts.build, scripts.start, dependencies
- [x] Write backend detection: Flask (app.py), Django (manage.py), FastAPI (main.py+uvicorn), Express (server.js+express)
- [x] Write frontend detection: Next.js (next.config), React (react in deps), Vue (vue in deps), Angular (angular.json)
- [x] Write Docker detection: Dockerfile, docker-compose.yml existence check
- [x] Write venv/runtime detection: .venv, backend/.venv, conda environment, node version
- [x] Write project type classification logic (fullstack/frontend_only/backend_only/monolith)
- [x] Write default value inference (ports, build commands, entry points per framework)
- [x] Write user confirmation prompt: present detected ProjectProfile, allow overrides
- [x] Handle edge cases: monorepo, no markers, conflicting markers
