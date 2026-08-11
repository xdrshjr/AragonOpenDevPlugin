# TODO 04: systemd Deployment Pipeline

**Spec Reference:** [specs/04-systemd-deployment.md](../specs/04-systemd-deployment.md)

## Dependencies

- `depends_on: [01, 02, 03]` — needs ProjectProfile, rendered templates, SSH connection
- `blocks: [07]` — verification needs running services
- `parallel_group: C`

## Tasks

- [x] Write dependency installation instructions in SKILL.md (using rendered install-deps.sh)
- [x] Write build execution logic: framework-specific build commands on server
- [x] Write service stop sequence: stop existing services before reinstall (idempotent)
- [x] Write template substitution execution: sed-based variable replacement on server
- [x] Write systemd unit installation: copy to /etc/systemd/system/
- [x] Write watchdog setup: install watchdog service + timer, chmod healthcheck.sh
- [x] Write logrotate setup: install logrotate config
- [x] Write systemd reload and enable sequence
- [x] Write service start sequence: backend first, wait for health, then frontend, then watchdog
- [x] Write Node.js resolution logic (resolve_node function generalization)
- [x] Write single-service project handling (frontend_only or backend_only)
- [x] Write framework-specific ExecStart generation (Flask, Django, FastAPI, Express, Next.js)
