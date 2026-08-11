# TODO 05: Docker Deployment Pipeline

**Spec Reference:** [specs/05-docker-deployment.md](../specs/05-docker-deployment.md)

## Dependencies

- `depends_on: [01, 02, 03]` — needs ProjectProfile, rendered templates, SSH connection
- `blocks: [07]` — verification needs running containers
- `parallel_group: C`

## Tasks

- [x] Write smart detection logic: existing Dockerfile/compose vs generate
- [x] Write project upload via SFTP (excluding node_modules, .venv, .git)
- [x] Write Dockerfile generation logic based on project type (node, python, fullstack)
- [x] Write docker-compose.yml generation with health checks and depends_on
- [x] Write .dockerignore generation
- [x] Write Docker build execution on server: docker compose build
- [x] Write container stop and start sequence: docker compose down/up -d
- [x] Write Docker-specific ops scripts: docker-deploy.sh, docker-status.sh, docker-logs.sh, docker-stop.sh
- [x] Write systemd-to-Docker migration handling (stop systemd services, backup)
- [x] Write container health waiting logic
