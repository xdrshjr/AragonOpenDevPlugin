# Spec 09: SKILL Workflow & User Interaction

## Purpose

Define the complete SKILL.md workflow: phase sequence, user interaction design, guided/auto modes, language selection, and integration with other specs.

## SKILL Metadata

```yaml
name: web-deployer
description: Deploy any web project to Linux servers with auto-detection, systemd/Docker service management, Nginx reverse proxy, and independent ops toolkit generation. Supports interactive guided mode and full-auto mode with multi-server batch deployment.
```

## Activation Triggers

The skill should activate when users mention:
- "deploy", "部署", "deployment"
- "server setup", "服务器部署"
- "systemd", "service registration"
- "web deploy", "web部署"
- "ops scripts", "运维脚本"
- `/web-deployer` slash command

## Phase Flow

```
Phase 1: Initialization & Language Selection
    ↓
Phase 2: Project Analysis
    ↓
Phase 3: Server Info Collection
    ↓
Phase 4: Deployment Configuration
    ↓
Phase 5: Template Rendering & Ops Generation
    ↓
Phase 6: Remote Deployment Execution
    ↓
Phase 7: Post-Deploy Verification
    ↓
Phase 8: Summary & Handoff
```

### Phase 1: Initialization & Language Selection

**AskUserQuestion #1**: Language

- Option 1: "中文 (Chinese)" — All interaction, generated README, script comments in Chinese
- Option 2: "English" — All interaction, generated README, script comments in English

**AskUserQuestion #2**: Deployment Mode

- Option 1: "Interactive guided mode (Recommended for first deploy)" — Step-by-step with confirmations
- Option 2: "Full-auto mode (for known environments)" — Minimal interaction, use defaults
- Option 3: "Generate ops scripts only (no deployment)" — Only create templates, don't execute

### Phase 2: Project Analysis

1. Scan current working directory (Spec 01)
2. Build ProjectProfile
3. Present detection results to user
4. In guided mode: confirm each field. In auto mode: show summary, proceed.

**AskUserQuestion**: Deployment type selection

- Option 1: "systemd (bare metal)" — Use systemd service management
- Option 2: "Docker" — Use Docker containers
- Option 3: "Both (generate configs for both)" — Generate both sets of templates
- Option 4: "Let the skill decide based on detection" — Auto-select based on Docker file presence

### Phase 3: Server Info Collection

1. Ask server connection details (Spec 03)
2. In guided mode: one question at a time. In auto mode: check env vars first.
3. Run pre-flight checks
4. Present pre-flight report
5. For multi-server: ask "Add another server?" loop

**Security**: Never store passwords. Use SSH_PASS env var or key auth.

### Phase 4: Deployment Configuration

1. Resolve all template variables (Spec 02)
2. In guided mode: present all detected/default values, allow overrides
3. Key decisions:

**AskUserQuestion**: Service naming confirmation

- Show auto-inferred `PROJECT_NAME`
- Allow override

**AskUserQuestion**: Nginx configuration

- Option 1: "Configure Nginx reverse proxy" → ask for domain
- Option 2: "Skip Nginx (I'll configure it myself)"
- Option 3: "Skip Nginx (no reverse proxy needed)"

**AskUserQuestion** (if Nginx): SSL configuration

- Option 1: "Auto-detect SSL certificates"
- Option 2: "HTTP only (no SSL)"
- Option 3: "I'll set up SSL later with certbot"

### Phase 5: Template Rendering & Ops Generation

1. Render all templates with resolved variables (Spec 02)
2. Generate ops/ directory locally (Spec 08)
3. Generate ops/README.md
4. In guided mode: show file list, ask for confirmation before upload
5. In auto mode: proceed directly

### Phase 6: Remote Deployment Execution

1. Upload ops/ and project files to server(s) via SFTP (Spec 03)
2. Execute deployment pipeline:
   - systemd mode: Spec 04 steps
   - Docker mode: Spec 05 steps
3. Configure Nginx if applicable (Spec 06)
4. Start services

For multi-server: execute sequentially (first deploy) or in parallel (redeploy)

### Phase 7: Post-Deploy Verification

1. Run verification tier based on user choice (Spec 07):

**AskUserQuestion**: Verification level

- Option 1: "Quick verification (health checks only)"
- Option 2: "Full verification (all checks)"
- Option 3: "Skip verification"

2. Present verification report
3. If failed: present failure report and user decision options (Spec 07)

### Phase 8: Summary & Handoff

Present comprehensive summary:

```
╔══════════════════════════════════════════════════╗
║  Deployment Complete                              ║
╠══════════════════════════════════════════════════╣
║  Project: my-webapp                               ║
║  Server:  10.0.1.10 (/home/deploy/my-webapp)    ║
║  Mode:    systemd                                 ║
║  Services:                                        ║
║    - my-webapp-backend  (port 5000)              ║
║    - my-webapp-frontend (port 3000)              ║
║    - my-webapp-watchdog (every 60s)              ║
║  Nginx:   example.com → localhost:3000           ║
║  SSL:     Let's Encrypt (expires 2026-06-15)     ║
╠══════════════════════════════════════════════════╣
║  Files generated:                                 ║
║  LOCAL:                                           ║
║    - ops/config.env                              ║
║    - ops/install.sh                              ║
║    - ops/deploy.sh (one-command redeploy)        ║
║    - ops/uninstall.sh                            ║
║    - ops/status.sh                               ║
║    - ops/logs.sh                                 ║
║    - ops/healthcheck.sh                          ║
║    - ops/README.md                               ║
║  SERVER: (same files at /home/deploy/my-webapp/) ║
╠══════════════════════════════════════════════════╣
║  Quick commands for future use:                   ║
║    Status:    ssh deploy@10.0.1.10 ./ops/status.sh║
║    Redeploy:  ssh deploy@10.0.1.10 ./ops/deploy.sh║
║    Logs:      ssh deploy@10.0.1.10 ./ops/logs.sh  ║
║    Uninstall: ssh deploy@10.0.1.10 sudo ./ops/uninstall.sh║
╚══════════════════════════════════════════════════╝
```

**AskUserQuestion**: Next steps

- Option 1: "Save server config to memory for future use"
- Option 2: "Deploy to another server"
- Option 3: "Done, end session"

## Auto Mode Behavior

In full-auto mode, the SKILL:
- Reads env vars for server info
- Uses all auto-detected defaults
- Skips confirmation prompts (except server credentials)
- Runs full verification automatically
- Reports results at the end

## Error Recovery

At any phase, if an error occurs:
1. Report the error clearly
2. Offer to retry the current step
3. Offer to go back to a previous phase
4. Never silently skip steps

## Integration with ssh-remote Skill

The SKILL uses paramiko for SSH operations (same pattern as ssh-remote skill):
- `ssh_connect()`, `ssh_exec()`, `sftp_upload()`, `sftp_download()`
- These helper functions are embedded in the SKILL.md as inline Python
- All SSH operations go through `Bash` tool executing Python scripts
