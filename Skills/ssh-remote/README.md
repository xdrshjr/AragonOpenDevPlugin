# SSH Remote Operations

A Claude Code skill for performing SSH operations on remote servers using Python `paramiko`.

## Why paramiko?

Native `ssh` + `sshpass` fails on Windows (no `sshpass` available), and piping passwords to `ssh` requires a TTY. `paramiko` is the reliable cross-platform solution that works on Windows, Linux, and macOS without requiring a TTY.

## Features

- **Execute Remote Commands** — Run single or batch commands with stdout/stderr/exit_code capture
- **Upload Files (SFTP)** — Upload files, multiple files, or entire directories recursively
- **Download Files (SFTP)** — Download remote files to local directory
- **Server Status Check** — Predefined command set (hostname, uname, df, free, nvidia-smi, uptime)
- **Cross-Platform** — Works on Windows, Linux, and macOS
- **Dual Auth** — Supports both password and SSH key authentication
- **Security-First** — Never stores credentials in files or memory; prefers env vars

## Trigger Phrases

```
"SSH into the server"
"connect to remote server"
"upload files to server"
"download from server"
"check server status"
"run command on remote machine"
"SFTP transfer"
```

## Quick Example

```python
import paramiko, os

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(
    hostname=os.environ["SSH_HOST"],
    username=os.environ["SSH_USER"],
    password=os.environ.get("SSH_PASS"),
)
try:
    stdin, stdout, stderr = ssh.exec_command("hostname && uname -a")
    print(stdout.read().decode())
finally:
    ssh.close()
```

## Security

- Credentials are **never** stored in files, memory, or git history
- Environment variables (`SSH_HOST`, `SSH_USER`, `SSH_PASS`, `SSH_KEY_PATH`) are the preferred credential source
- SSH key authentication is preferred over password authentication
- Users are prompted for credentials at runtime when env vars are not set

## License

MIT
