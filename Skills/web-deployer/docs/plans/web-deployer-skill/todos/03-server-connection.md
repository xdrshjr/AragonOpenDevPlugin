# TODO 03: Server Connection & Management

**Spec Reference:** [specs/03-server-connection.md](../specs/03-server-connection.md)

## Dependencies

- `depends_on: []` — no dependencies, foundational module
- `blocks: [04, 05, 06, 07]` — all remote operations depend on SSH
- `parallel_group: A`

## Tasks

- [x] Write SSH helper functions in SKILL.md: ssh_connect, ssh_exec, sftp_makedirs, sftp_upload, sftp_download (reuse ssh-remote pattern)
- [x] Write server info collection prompts: host, port, username, auth method, remote dir
- [x] Write multi-server collection loop: "Add another server?" with list management
- [x] Write auto-mode server detection: read from env vars (SSH_HOST, SSH_USER, etc.)
- [x] Write config file mode: read from deploy-servers.json
- [x] Write memory mode: search auto-memory for saved server configs
- [x] Write pre-flight check sequence: connectivity, write permission, Python, Node, Docker, Nginx, systemd, disk, memory
- [x] Write pre-flight report formatting and presentation
- [x] Write pre-flight failure handling: per-check fallback actions
- [x] Write connection reuse pattern: maintain SSH session across deployment steps
- [x] Write security rules in SKILL.md: never store passwords, prefer key auth, env var pattern
- [x] Write multi-server orchestration: sequential (first deploy) and parallel (redeploy) modes
- [x] Write per-server config management (different remote_dir, domain, ports per server)
