# web-deployer

Deploy any web project to Linux servers with a single Claude Code command.

## What It Does

`web-deployer` auto-detects your project type, generates a complete ops toolkit, deploys to one or more Linux servers via SSH, and verifies everything is running. It supports:

- **Auto-detection**: Next.js, React, Vue, Angular, Flask, Django, FastAPI, Express, NestJS, and more
- **Two deployment modes**: systemd (bare metal) or Docker
- **Nginx reverse proxy**: HTTPS with SSL auto-detection, SSE/WebSocket support
- **Multi-server batch deployment**: Deploy to N servers in one run
- **Independent ops toolkit**: Generated `ops/` scripts work without Claude Code
- **Three automation levels**: Interactive guided, full-auto, or scripts-only

## Quick Start

```
/web-deployer
```

Or describe your intent:

```
Deploy this project to my server at 10.0.1.10
部署这个项目到服务器
```

## Workflow

```
Phase 1: Language + Mode selection
Phase 2: Project analysis (auto-detect frameworks, ports, structure)
Phase 3: Server connection (SSH details, pre-flight checks)
Phase 4: Configuration (variables, Nginx, SSL decisions)
Phase 5: Template rendering (generate ops/ toolkit)
Phase 6: Remote deployment (systemd or Docker + Nginx)
Phase 7: Verification (health checks, failure handling, rollback)
Phase 8: Summary (report, quick commands, memory save)
```

## Supported Frameworks

| Frontend | Backend |
|----------|---------|
| Next.js | Flask |
| Nuxt.js | Django |
| React (CRA/Vite) | FastAPI |
| Vue (Vite/CLI) | Express |
| Angular | NestJS |
| Static sites | Fastify / Koa |

## Generated Ops Toolkit

After deployment, your project gets an independent `ops/` directory:

| Script | Purpose |
|--------|---------|
| `ops/config.env` | Centralized configuration |
| `ops/deploy.sh` | One-command redeploy (git pull → build → restart) |
| `ops/install.sh` | Register systemd services, watchdog, Nginx |
| `ops/install-deps.sh` | Install project dependencies |
| `ops/uninstall.sh` | Remove all services and configs |
| `ops/status.sh` | Service status dashboard |
| `ops/logs.sh` | View service logs |
| `ops/healthcheck.sh` | Watchdog health check |

These scripts are self-contained — they work without Claude Code, powered only by `config.env`.

## Requirements

**Local machine:**
- Claude Code with `ssh-remote` skill pattern (paramiko)

**Target server:**
- Linux with systemd (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- Python 3.8+ and/or Node.js 18+ (depending on project)
- Nginx (optional, for reverse proxy)
- Docker + Docker Compose (optional, for Docker mode)

## Modes

### Interactive Guided
Step-by-step with confirmations at every decision point. Recommended for first deployments.

### Full-Auto
Reads environment variables and detected defaults. Minimal interaction — only prompts for server credentials.

### Scripts-Only
Generates the ops toolkit locally without deploying. Useful for review or CI/CD integration.

## Multi-Server Deployment

Deploy to multiple servers in a single session. Each server gets its own `config.env` with server-specific values (domain, SSL paths, etc.).

## Rollback

If deployment verification fails, choose from:
- **Retry**: Re-run from the build step
- **Rollback**: Restore from automatic pre-deployment backup
- **Manual fix**: Get SSH access and diagnostic commands
- **Skip**: Continue with other servers (multi-server only)

## Language Support

All interaction and generated documentation supports English and Chinese (中文). Choose at session start.
