# TODO 08: Ops Toolkit Generation

**Spec Reference:** [specs/08-ops-toolkit-generation.md](../specs/08-ops-toolkit-generation.md)

## Dependencies

- `depends_on: [01, 02]` — needs ProjectProfile and template system
- `blocks: [04, 05, 06]` — deployment pipelines use the generated ops scripts
- `parallel_group: B`

## Tasks

- [x] Write ops directory creation logic (local and remote)
- [x] Write config.env rendering with all detected/user-provided values
- [x] Write install.sh generalization: replace hardcoded InkClaw references with {{PROJECT_NAME}}
- [x] Write install-deps.sh generalization: support multiple backend/frontend frameworks
- [x] Write uninstall.sh generalization: use {{PROJECT_NAME}} prefix
- [x] Write status.sh generalization: configurable service names, health endpoints
- [x] Write logs.sh generalization: configurable service names
- [x] Write healthcheck.sh generalization: configurable health URLs from config.env
- [x] Write deploy.sh (new): one-command git pull + deps + build + install
- [x] Write Docker-specific ops scripts: docker-deploy.sh, docker-status.sh, docker-logs.sh, docker-stop.sh
- [x] Write ops/README.md generation (language-aware, includes usage, config reference, troubleshooting)
- [x] Write local ops/ placement (in user's project directory)
- [x] Write remote ops/ upload via SFTP with correct permissions (chmod +x)
- [x] Write .gitignore recommendations
