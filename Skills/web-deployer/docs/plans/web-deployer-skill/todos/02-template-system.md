# TODO 02: Template System

**Spec Reference:** [specs/02-template-system.md](../specs/02-template-system.md)

## Dependencies

- `depends_on: [01]` — needs ProjectProfile for variable definitions
- `blocks: [04, 05, 06, 08]` — all deployment pipelines and ops generation use templates
- `parallel_group: B`

## Tasks

- [x] Define template placeholder syntax documentation in SKILL.md ({{VAR}}, {{IF}}/{{ENDIF}}, {{IF_NOT}}/{{ENDIF_NOT}})
- [x] Document complete variable registry: auto-detected, user-provided, computed variables
- [x] Write variable resolution pipeline instructions in SKILL.md
- [x] Create `templates/ops/config.env.tpl` — generalized from InkClaw config.env
- [x] Create `templates/ops/install.sh.tpl` — generalized from InkClaw install.sh
- [x] Create `templates/ops/install-deps.sh.tpl` — generalized from InkClaw install-deps.sh
- [x] Create `templates/ops/uninstall.sh.tpl` — generalized from InkClaw uninstall.sh
- [x] Create `templates/ops/status.sh.tpl` — generalized from InkClaw status.sh
- [x] Create `templates/ops/logs.sh.tpl` — generalized from InkClaw logs.sh
- [x] Create `templates/ops/healthcheck.sh.tpl` — generalized from InkClaw healthcheck.sh
- [x] Create `templates/ops/deploy.sh.tpl` — new one-command redeploy script
- [x] Create `templates/systemd/backend.service.tpl` — generalized backend unit
- [x] Create `templates/systemd/frontend.service.tpl` — generalized frontend unit
- [x] Create `templates/systemd/watchdog.service.tpl` — generalized watchdog
- [x] Create `templates/systemd/watchdog.timer.tpl` — generalized timer
- [x] Create `templates/systemd/logrotate.tpl` — generalized logrotate config
- [x] Create `templates/nginx/site-https.tpl` — HTTPS + SSL + SSE
- [x] Create `templates/nginx/site-http.tpl` — HTTP-only + SSE
- [x] Create `templates/docker/Dockerfile.node.tpl` — Node.js app container
- [x] Create `templates/docker/Dockerfile.python.tpl` — Python app container
- [x] Create `templates/docker/Dockerfile.fullstack.tpl` — multi-stage fullstack
- [x] Create `templates/docker/docker-compose.tpl` — multi-service compose
- [x] Write template validation rules (no unresolved placeholders, bash -n syntax check)
