---
name: ssh-remote
description: Execute commands, upload/download files, and check status on remote servers via SSH/SFTP using Python paramiko. Use when the user mentions SSH, remote server, upload to server, download from server, SFTP, SCP, server status, or running commands on a remote machine.
---

# SSH Remote Operations

Use Python `paramiko` for all SSH/SFTP operations. Works cross-platform (Windows, Linux, macOS) without requiring a TTY.

## Prerequisites

```python
try:
    import paramiko
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "paramiko"])
    import paramiko
```

## Decision Tree

```
User task → What operation?
  ├─ Execute remote command(s) → ssh_exec()
  ├─ Upload file(s) → sftp_upload()
  ├─ Download file(s) → sftp_download()
  ├─ Check server status → ssh_exec() with STATUS_COMMANDS
  └─ Batch operations → Combine in single SSH session
```

## Connection

```python
import paramiko, os

def ssh_connect(host, username, password=None, key_path=None, port=22, timeout=10):
    """Connect via password or SSH key. Returns SSHClient."""
    ssh = paramiko.SSHClient()
    # AutoAddPolicy accepts unknown host keys - acceptable for trusted networks.
    # For production, use paramiko.WarningPolicy() or load known_hosts.
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    kwargs = dict(hostname=host, port=port, username=username, timeout=timeout)
    if key_path:
        kwargs["key_filename"] = key_path
    elif password:
        kwargs["password"] = password
    ssh.connect(**kwargs)
    return ssh
```

## Operations

### Execute Remote Commands

```python
def ssh_exec(ssh, commands):
    """Execute commands and print output. commands: str or list[str]."""
    if isinstance(commands, str):
        commands = [commands]
    results = []
    for cmd in commands:
        stdin, stdout, stderr = ssh.exec_command(cmd)
        out = stdout.read().decode()
        err = stderr.read().decode()
        exit_code = stdout.channel.recv_exit_status()
        results.append({"cmd": cmd, "stdout": out, "stderr": err, "exit_code": exit_code})
        if out: print(out, end="")
        if err: print(f"[STDERR] {err}", end="")
    return results
```

### Upload Files (SFTP)

```python
import os

def sftp_makedirs(sftp, remote_dir):
    """Recursively create remote directories."""
    dirs_to_create = []
    current = remote_dir
    while current and current != "/":
        try:
            sftp.stat(current)
            break
        except FileNotFoundError:
            dirs_to_create.append(current)
            current = current.rsplit("/", 1)[0]
    for d in reversed(dirs_to_create):
        sftp.mkdir(d)

def sftp_upload(ssh, local_paths, remote_dir):
    """Upload local file(s) to remote directory. Creates remote_dir recursively if needed."""
    sftp = ssh.open_sftp()
    try:
        sftp_makedirs(sftp, remote_dir)

        if isinstance(local_paths, str):
            local_paths = [local_paths]

        for local_path in local_paths:
            if os.path.isdir(local_path):
                for root, dirs, files in os.walk(local_path):
                    rel = os.path.relpath(root, local_path)
                    rd = f"{remote_dir}/{rel}".replace("\\", "/").rstrip("/.")
                    sftp_makedirs(sftp, rd)
                    for f in files:
                        lp = os.path.join(root, f)
                        rp = f"{rd}/{f}"
                        size_mb = os.path.getsize(lp) / 1024 / 1024
                        print(f"Uploading: {f} ({size_mb:.1f} MB) ...", end=" ")
                        sftp.put(lp, rp)
                        print("OK")
            else:
                fname = os.path.basename(local_path)
                remote_path = f"{remote_dir}/{fname}"
                size_mb = os.path.getsize(local_path) / 1024 / 1024
                print(f"Uploading: {fname} ({size_mb:.1f} MB) ...", end=" ")
                sftp.put(local_path, remote_path)
                print("OK")
    finally:
        sftp.close()
```

### Download Files (SFTP)

```python
def sftp_download(ssh, remote_paths, local_dir):
    """Download remote file(s) to local directory. For recursive download, use sftp.listdir_attr() to walk remote dirs."""
    sftp = ssh.open_sftp()
    try:
        os.makedirs(local_dir, exist_ok=True)

        if isinstance(remote_paths, str):
            remote_paths = [remote_paths]

        for remote_path in remote_paths:
            fname = remote_path.rsplit("/", 1)[-1]
            local_path = os.path.join(local_dir, fname)
            print(f"Downloading: {fname} ...", end=" ")
            sftp.get(remote_path, local_path)
            size_mb = os.path.getsize(local_path) / 1024 / 1024
            print(f"OK ({size_mb:.1f} MB)")
    finally:
        sftp.close()
```

### Server Status Check

```python
# These commands assume a Linux/macOS remote host.
# For Windows servers, adjust to: systeminfo, wmic, etc.
STATUS_COMMANDS = [
    "hostname",
    "uname -a",
    "df -h",
    "free -h",
    "nvidia-smi 2>/dev/null || echo 'No GPU detected'",
    "uptime",
    "whoami",
]

def check_server_status(ssh):
    """Run standard server status commands."""
    return ssh_exec(ssh, STATUS_COMMANDS)
```

## Complete Usage Pattern

Always use `try/finally` to ensure the connection is closed:

```python
import os

ssh = ssh_connect(
    host=os.environ.get("SSH_HOST", "1.2.3.4"),
    username=os.environ.get("SSH_USER", "user"),
    password=os.environ.get("SSH_PASS"),
    key_path=os.environ.get("SSH_KEY_PATH"),
)
try:
    ssh_exec(ssh, ["ls -la", "cat /etc/os-release"])
    sftp_upload(ssh, ["local/file.txt", "local/dir/"], "/home/user/dest")
    sftp_download(ssh, ["/home/user/data.csv"], "local/downloads")
    check_server_status(ssh)
finally:
    ssh.close()
```

## Security Rules

<IMPORTANT>
1. **NEVER store passwords** in skill files, CLAUDE.md, code files, or git history
2. **NEVER save passwords to memory** — only store host, username, and default remote paths
3. **Prefer environment variables** for credentials: `SSH_HOST`, `SSH_USER`, `SSH_PASS`, `SSH_KEY_PATH`
4. **Prefer SSH key auth** over password auth when available
5. **Always ask the user** for credentials at runtime if not provided via env vars
</IMPORTANT>

## Memory Pattern

When the user connects to a server, save connection metadata (NOT credentials) to auto-memory as a `reference` type. Store: host, username, default remote path, OS, GPU info, and relevant notes.

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| `AuthenticationException` | Wrong password or key | Ask user to verify credentials |
| `NoValidConnectionsError` | Host unreachable | Check host/port, firewall, VPN |
| `socket.timeout` | Network timeout | Increase timeout or check connectivity |
| `FileNotFoundError` (SFTP) | Remote path doesn't exist | Create directory with `sftp_makedirs()` |
| `PermissionError` (SFTP) | No write access | Check remote file permissions |

## Long-Running Commands

Paramiko `exec_command` timeout controls channel open, not execution time. Set read timeout on the channel:

```python
stdin, stdout, stderr = ssh.exec_command("long_running_script.sh")
stdout.channel.settimeout(600)  # 10-minute read timeout
output = stdout.read().decode()
```
