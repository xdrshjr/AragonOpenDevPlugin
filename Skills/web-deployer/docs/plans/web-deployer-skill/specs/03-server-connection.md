# Spec 03: Server Connection & Management

## Purpose

Handle SSH/SFTP connections to target servers, support multi-server orchestration, pre-flight validation, and provide the remote execution layer for all deployment operations.

## Connection Methods

### Primary: SSH Key Authentication

```python
ssh = ssh_connect(host=server.host, username=server.user, key_path=server.key_path, port=server.port)
```

### Fallback: Password Authentication

```python
# Password from environment variable — NEVER stored in files
password = os.environ.get("SSH_PASS")
ssh = ssh_connect(host=server.host, username=server.user, password=password, port=server.port)
```

### Connection Reuse

For multi-step deployment, maintain the SSH connection across steps rather than reconnecting for each command. Close connection only at phase completion or on error.

## Server Info Collection

### Interactive Mode

Ask via sequential `AskUserQuestion` calls:

1. **Host**: IP address or hostname (required)
2. **SSH Port**: Default 22
3. **Username**: SSH login user (required)
4. **Auth method**: SSH key path or "password via SSH_PASS env var"
5. **Remote project directory**: Where to deploy (e.g., `/home/deploy/my-webapp`)
6. **Purpose**: "deploy" (always, for this skill)

### Multi-Server Mode

After first server info collected, ask: "Add another server?"

If yes, repeat collection. Store as list:

```
servers: [
  { name: "prod-1", host: "10.0.1.10", port: 22, user: "deploy", key_path: "~/.ssh/id_rsa", remote_dir: "/opt/my-webapp" },
  { name: "prod-2", host: "10.0.1.11", port: 22, user: "deploy", key_path: "~/.ssh/id_rsa", remote_dir: "/opt/my-webapp" },
]
```

### Auto Mode

Read server config from:
1. Environment variables: `SSH_HOST`, `SSH_USER`, `SSH_KEY_PATH`, `SSH_PORT`, `REMOTE_DIR`
2. Config file: `deploy-servers.json` in project root
3. Auto-memory: Previously saved server configurations

## Pre-Flight Checks

Before any deployment operation, validate each server:

```python
ssh = ssh_connect(...)
try:
    checks = ssh_exec(ssh, [
        "echo 'CONNECTION OK'",                              # 1. Connectivity
        f"mkdir -p {remote_dir}",                            # 2. Write permission
        "python3 --version 2>/dev/null || echo 'NO_PYTHON'", # 3. Python available
        "node --version 2>/dev/null || echo 'NO_NODE'",      # 4. Node available
        "docker --version 2>/dev/null || echo 'NO_DOCKER'",  # 5. Docker available
        "nginx -v 2>&1 || echo 'NO_NGINX'",                 # 6. Nginx available
        "systemctl --version 2>/dev/null || echo 'NO_SYSTEMD'", # 7. systemd available
        "df -h / | tail -1",                                 # 8. Disk space
        "free -h | head -2",                                 # 9. Memory
    ])
finally:
    ssh.close()
```

### Pre-Flight Report

Present to user:

```
Server: prod-1 (10.0.1.10)
├── Connection:  ✓ OK
├── Write access: ✓ /opt/my-webapp
├── Python:      ✓ 3.10.12
├── Node.js:     ✓ v20.11.0
├── Docker:      ✓ 24.0.7
├── Nginx:       ✓ 1.24.0
├── systemd:     ✓ 252
├── Disk:        45G free / 100G
└── Memory:      8G total / 3.2G available
```

### Pre-Flight Failure Handling

| Check | If Failed | Action |
|-------|-----------|--------|
| Connection | Cannot proceed | Ask user to fix credentials |
| Write permission | Cannot deploy | Ask user to check permissions |
| Python missing | Cannot use Python backend | Warn; offer to install or skip backend |
| Node missing | Cannot use Node frontend | Warn; offer to install via nvm or skip |
| Docker missing | Cannot use Docker mode | Fall back to systemd mode |
| Nginx missing | Cannot configure reverse proxy | Skip Nginx config, warn user |
| systemd missing | Cannot use systemd mode | Fall back to Docker mode |
| Low disk | Risk of failed deploy | Warn with specific numbers |
| Low memory | Risk of OOM | Warn with specific numbers |

## File Transfer Protocol

### Upload (Local → Server)

```python
sftp_upload(ssh, local_paths=["ops/"], remote_dir=f"{remote_dir}/ops/")
```

Upload strategy:
1. **Initial deploy**: Upload entire `ops/` directory + project files
2. **Redeploy**: Upload only changed files (compare timestamps or checksums)

### Download (Server → Local)

Used for:
- Downloading server-generated configs for backup
- Downloading logs for analysis
- Downloading verification results

## Security Rules

1. **NEVER** store passwords in any file (templates, configs, scripts, memory)
2. **NEVER** log or echo passwords in command output
3. **Prefer** SSH key authentication over passwords
4. **Use** environment variables for sensitive values: `SSH_PASS`, `SSH_KEY_PATH`
5. **Save** to auto-memory: host, username, key_path, remote_dir, purpose only
6. **Validate** SSH host key (warn on first connection, reject on mismatch)

## Multi-Server Orchestration

### Sequential Mode (default for first deploy)

Deploy to servers one at a time. If any server fails, pause and ask user:
- Continue with remaining servers
- Retry failed server
- Abort all

### Parallel Mode (for redeploy)

When redeploying to multiple known-good servers, deploy in parallel using background agents.

### Per-Server Config

Each server may have different:
- `remote_dir` (project location)
- `NGINX_DOMAIN` (different domains per server)
- Port mappings
- SSL certificate paths

Store per-server overrides in `deploy-servers.json`.
