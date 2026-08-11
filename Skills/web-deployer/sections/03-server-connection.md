<!-- Section: Server Connection & Management -->
<!-- Author: google-dev-02 -->
<!-- Integrates into: SKILL.md Phase 3 + SSH Helper Infrastructure -->
<!-- Consumed by: dev-05 (systemd/docker), dev-06 (nginx), dev-07 (verification), dev-08 (integrator) -->

## SSH Helper Infrastructure

> This section defines the SSH/SFTP helper functions used throughout all deployment phases. All remote operations use Python `paramiko` via the `Bash` tool. These functions are called inline — the skill does NOT generate standalone Python scripts.

### Prerequisites

Before any SSH operation, ensure `paramiko` is available:

```python
try:
    import paramiko
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "paramiko"])
    import paramiko
import os, stat, json, time
```

### ssh_connect

```python
def ssh_connect(host, username, password=None, key_path=None, port=22, timeout=15):
    """
    Establish SSH connection to a remote server.

    Auth priority: key_path > password > SSH agent.
    Returns paramiko.SSHClient on success.
    Raises paramiko.AuthenticationException, socket.timeout, etc. on failure.
    """
    ssh = paramiko.SSHClient()
    # AutoAddPolicy for trusted deployment targets.
    # The pre-flight check warns the user on first connection.
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    kwargs = dict(hostname=host, port=port, username=username, timeout=timeout)
    if key_path:
        expanded = os.path.expanduser(key_path)
        if not os.path.isfile(expanded):
            raise FileNotFoundError(f"SSH key not found: {expanded}")
        kwargs["key_filename"] = expanded
    elif password:
        kwargs["password"] = password
    # If neither key nor password, paramiko falls back to SSH agent / default keys
    ssh.connect(**kwargs)
    return ssh
```

### ssh_exec

```python
def ssh_exec(ssh, commands, timeout=120):
    """
    Execute one or more commands on the remote server.

    Args:
        ssh: paramiko.SSHClient (connected)
        commands: str or list[str]
        timeout: per-command read timeout in seconds (default 120)

    Returns:
        list[dict] — each dict has keys: cmd, stdout, stderr, exit_code
    """
    if isinstance(commands, str):
        commands = [commands]
    results = []
    for cmd in commands:
        stdin, stdout, stderr = ssh.exec_command(cmd)
        stdout.channel.settimeout(timeout)
        try:
            out = stdout.read().decode("utf-8", errors="replace")
            err = stderr.read().decode("utf-8", errors="replace")
        except Exception as e:
            out = ""
            err = f"Read timeout or channel error: {e}"
        exit_code = stdout.channel.recv_exit_status()
        results.append({
            "cmd": cmd,
            "stdout": out.strip(),
            "stderr": err.strip(),
            "exit_code": exit_code,
        })
    return results
```

### ssh_exec_long

```python
def ssh_exec_long(ssh, command, timeout=600):
    """
    Execute a long-running command (e.g., npm install, docker build).
    Streams stdout line by line for progress visibility.
    Returns single result dict.
    """
    stdin, stdout, stderr = ssh.exec_command(command)
    stdout.channel.settimeout(timeout)
    lines = []
    try:
        for line in iter(stdout.readline, ""):
            line_str = line.strip()
            if line_str:
                print(line_str)
                lines.append(line_str)
    except Exception as e:
        lines.append(f"[stream interrupted: {e}]")
    err = stderr.read().decode("utf-8", errors="replace").strip()
    exit_code = stdout.channel.recv_exit_status()
    return {
        "cmd": command,
        "stdout": "\n".join(lines),
        "stderr": err,
        "exit_code": exit_code,
    }
```

### sftp_makedirs

```python
def sftp_makedirs(sftp, remote_dir):
    """Recursively create remote directories (like mkdir -p)."""
    dirs_to_create = []
    current = remote_dir
    while current and current != "/":
        try:
            sftp.stat(current)
            break  # This directory exists; stop climbing
        except (IOError, OSError):
            dirs_to_create.append(current)
            current = current.rsplit("/", 1)[0] if "/" in current else ""
    for d in reversed(dirs_to_create):
        try:
            sftp.mkdir(d)
        except IOError:
            pass  # May already exist due to race condition or symlink
```

### sftp_upload

```python
def sftp_upload(ssh, local_paths, remote_dir, progress=True):
    """
    Upload local file(s) or directory tree to remote_dir.

    Args:
        ssh: connected paramiko.SSHClient
        local_paths: str or list[str] — files or directories to upload
        remote_dir: absolute remote path (created if missing)
        progress: print upload progress (default True)
    """
    sftp = ssh.open_sftp()
    try:
        sftp_makedirs(sftp, remote_dir)

        if isinstance(local_paths, str):
            local_paths = [local_paths]

        uploaded_count = 0
        for local_path in local_paths:
            if os.path.isdir(local_path):
                for root, dirs, files in os.walk(local_path):
                    rel = os.path.relpath(root, local_path)
                    rd = f"{remote_dir}/{rel}".replace("\\", "/")
                    if rd.endswith("/."):
                        rd = rd[:-2]
                    sftp_makedirs(sftp, rd)
                    for f in files:
                        lp = os.path.join(root, f)
                        rp = f"{rd}/{f}"
                        if progress:
                            size_mb = os.path.getsize(lp) / (1024 * 1024)
                            print(f"  Upload: {os.path.relpath(lp, local_path)} ({size_mb:.1f} MB)")
                        sftp.put(lp, rp)
                        uploaded_count += 1
            elif os.path.isfile(local_path):
                fname = os.path.basename(local_path)
                rp = f"{remote_dir}/{fname}"
                if progress:
                    size_mb = os.path.getsize(local_path) / (1024 * 1024)
                    print(f"  Upload: {fname} ({size_mb:.1f} MB)")
                sftp.put(local_path, rp)
                uploaded_count += 1
            else:
                print(f"  WARNING: Skipping {local_path} (not found)")

        if progress:
            print(f"  Uploaded {uploaded_count} file(s) to {remote_dir}")
    finally:
        sftp.close()
```

### sftp_download

```python
def sftp_download(ssh, remote_paths, local_dir, progress=True):
    """
    Download remote file(s) to local_dir.

    Args:
        ssh: connected paramiko.SSHClient
        remote_paths: str or list[str] — remote file paths
        local_dir: local destination directory (created if missing)
        progress: print download progress (default True)
    """
    sftp = ssh.open_sftp()
    try:
        os.makedirs(local_dir, exist_ok=True)

        if isinstance(remote_paths, str):
            remote_paths = [remote_paths]

        for rp in remote_paths:
            fname = rp.rsplit("/", 1)[-1]
            local_path = os.path.join(local_dir, fname)
            if progress:
                print(f"  Download: {fname} ...", end=" ")
            sftp.get(rp, local_path)
            if progress:
                size_mb = os.path.getsize(local_path) / (1024 * 1024)
                print(f"OK ({size_mb:.1f} MB)")
    finally:
        sftp.close()
```

### Connection Reuse Pattern

Throughout the deployment workflow (Phases 3-7), the skill maintains a single SSH connection per server rather than reconnecting for each operation. The connection is stored in a `server_context` dict and passed between phases:

```python
# server_context structure — created in Phase 3, used through Phase 7
server_context = {
    "name": "prod-1",                  # Human-friendly server name
    "host": "10.0.1.10",
    "port": 22,
    "user": "deploy",
    "key_path": "~/.ssh/id_rsa",       # Or None if password auth
    "remote_dir": "/opt/my-webapp",
    "ssh": None,                        # Active paramiko.SSHClient (set after connect)
    "preflight": {},                    # Pre-flight check results (set in Phase 3)
    "per_server_config": {},            # Per-server overrides (domain, ports, SSL paths)
}
```

**Connection lifecycle:**
1. **Phase 3 (this section):** Open connection, run pre-flight checks, keep `ssh` alive in context
2. **Phase 5 (template rendering):** Reuse connection for remote path validation
3. **Phase 6 (deployment execution):** Reuse connection for all uploads and remote commands
4. **Phase 7 (verification):** Reuse connection for health checks
5. **Phase 8 (summary):** Close connection in `finally` block

```python
# Reconnect helper — used if connection drops during long deployment
def ensure_connected(ctx):
    """Re-establish SSH connection if it was lost."""
    ssh = ctx.get("ssh")
    if ssh is None or ssh.get_transport() is None or not ssh.get_transport().is_active():
        print(f"  Reconnecting to {ctx['name']} ({ctx['host']})...")
        password = os.environ.get("SSH_PASS") if not ctx.get("key_path") else None
        ctx["ssh"] = ssh_connect(
            host=ctx["host"],
            username=ctx["user"],
            key_path=ctx.get("key_path"),
            password=password,
            port=ctx.get("port", 22),
        )
    return ctx["ssh"]
```

---

### Phase 3: Server Info Collection

**Goal:** Collect connection details for one or more target servers, validate connectivity and server capabilities, and build the `server_contexts` list used by all subsequent phases.

**Entry conditions:** Phase 2 (Project Analysis) has completed and `project_profile` is available.

#### Step 3.1: Determine Server Info Source

The skill supports four sources for server connection info, checked in this order:

**In AUTO mode** (user selected full-auto in Phase 1):

1. **Environment variables** — checked first
2. **Config file** (`deploy-servers.json` in project root) — checked second
3. **Auto-memory** — checked third
4. If none found, fall back to interactive prompts

**In INTERACTIVE mode:**

1. Ask user directly via `AskUserQuestion` prompts

#### Step 3.2: Auto Mode — Environment Variable Detection

Check for standard environment variables:

```python
env_host = os.environ.get("DEPLOY_HOST")
env_user = os.environ.get("DEPLOY_USER")
env_key = os.environ.get("DEPLOY_KEY")
env_port = os.environ.get("DEPLOY_PORT", "22")
env_dir = os.environ.get("DEPLOY_DIR")
```

If `DEPLOY_HOST` and `DEPLOY_USER` are both set, construct a server entry:

```python
if env_host and env_user:
    server = {
        "name": env_host.split(".")[0],  # Derive name from hostname
        "host": env_host,
        "port": int(env_port),
        "user": env_user,
        "key_path": env_key,  # May be None — password from SSH_PASS at connect time
        "remote_dir": env_dir or f"/home/{env_user}/{project_profile['name']}",
    }
    servers = [server]
    print(f"Server config loaded from environment variables: {env_host}")
```

#### Step 3.3: Auto Mode — Config File Detection

Look for `deploy-servers.json` in the project root:

```python
config_path = os.path.join(project_root, "deploy-servers.json")
```

Expected format:

```json
{
  "servers": [
    {
      "name": "prod-1",
      "host": "10.0.1.10",
      "port": 22,
      "user": "deploy",
      "key_path": "~/.ssh/id_rsa",
      "remote_dir": "/opt/my-webapp",
      "config_overrides": {
        "NGINX_DOMAIN": "example.com",
        "BACKEND_PORT": 5000,
        "FRONTEND_PORT": 3000,
        "SSL_CERT_PATH": "/etc/letsencrypt/live/example.com/fullchain.pem",
        "SSL_KEY_PATH": "/etc/letsencrypt/live/example.com/privkey.pem"
      }
    },
    {
      "name": "prod-2",
      "host": "10.0.1.11",
      "port": 22,
      "user": "deploy",
      "key_path": "~/.ssh/id_rsa",
      "remote_dir": "/opt/my-webapp",
      "config_overrides": {
        "NGINX_DOMAIN": "staging.example.com"
      }
    }
  ]
}
```

Read and parse:

```python
if os.path.isfile(config_path):
    with open(config_path, "r") as f:
        config = json.load(f)
    servers = config.get("servers", [])
    # Validate required fields
    for s in servers:
        assert s.get("host"), f"Server entry missing 'host': {s}"
        assert s.get("user"), f"Server entry missing 'user': {s}"
        s.setdefault("port", 22)
        s.setdefault("name", s["host"].split(".")[0])
        s.setdefault("remote_dir", f"/home/{s['user']}/{project_profile['name']}")
    print(f"Loaded {len(servers)} server(s) from deploy-servers.json")
```

#### Step 3.4: Auto Mode — Memory Detection

Search auto-memory for previously saved server configurations:

```
Use Grep to search the user's auto-memory directory (~/.claude/ or the project .claude/ directory)
for files containing "reference_server" or matching the pattern "host.*deploy".
```

If a matching memory file is found, parse the server details (host, username, key_path, remote_dir) and confirm with the user before reusing:

```
AskUserQuestion:
  "Found saved server config in memory: {server_name} ({host}).
   Use this server for deployment?"
  candidates:
    - "Yes, use this server"
    - "Yes, but update the remote directory"
    - "No, enter server info manually"
```

#### Step 3.5: Interactive Mode — Server Info Collection

Collect server details through sequential `AskUserQuestion` calls:

**Question 1: Host**
```
AskUserQuestion:
  "Enter the target server's IP address or hostname:"
  (freeform — no candidates, user types the value)
```

**Question 2: SSH Port**
```
AskUserQuestion:
  "SSH port for {host}?"
  candidates:
    - "22 (default)"
    - "Other (specify)"
```

**Question 3: Username**
```
AskUserQuestion:
  "SSH username for {host}:"
  (freeform — no candidates)
```

**Question 4: Authentication Method**
```
AskUserQuestion:
  "Authentication method for {user}@{host}?"
  candidates:
    - "SSH key (specify path)"
    - "SSH key (default ~/.ssh/id_rsa)"
    - "SSH key (default ~/.ssh/id_ed25519)"
    - "Password (via SSH_PASS environment variable)"
```

If user selects "SSH key (specify path)":
```
AskUserQuestion:
  "Enter the path to your SSH private key:"
  (freeform — no candidates)
```

**Question 5: Remote Directory**
```
AskUserQuestion:
  "Remote directory for deployment?
   This is where your project files and ops/ scripts will live on the server."
  candidates:
    - "/opt/{project_name}"
    - "/home/{user}/{project_name}"
    - "/var/www/{project_name}"
    - "Other (specify)"
```

#### Step 3.6: Multi-Server Collection Loop

After the first server's info is collected (from any source), ask whether to add more:

```
AskUserQuestion:
  "Server 1 configured: {name} ({user}@{host}:{port} → {remote_dir}).
   Add another deployment target?"
  candidates:
    - "No, deploy to this server only"
    - "Yes, add another server"
```

If "Yes", repeat Step 3.5 for the next server. Continue the loop until the user selects "No".

After the loop, display a summary:

```
Deployment Targets:
  1. prod-1  →  deploy@10.0.1.10:22  →  /opt/my-webapp
  2. prod-2  →  deploy@10.0.1.11:22  →  /opt/my-webapp

Proceeding to pre-flight checks...
```

#### Step 3.7: Pre-Flight Check Sequence

For each server in the `servers` list, establish a connection and run the full pre-flight check battery.

```python
def run_preflight_checks(server):
    """
    Run all pre-flight checks on a single server.
    Returns dict of check_name -> {status, detail, version}.
    """
    results = {}

    # --- 1. Connectivity ---
    try:
        password = os.environ.get("SSH_PASS") if not server.get("key_path") else None
        ssh = ssh_connect(
            host=server["host"],
            username=server["user"],
            key_path=server.get("key_path"),
            password=password,
            port=server.get("port", 22),
        )
        results["connection"] = {"status": "ok", "detail": "SSH connection established"}
    except Exception as e:
        results["connection"] = {"status": "fail", "detail": str(e)}
        return results, None  # Cannot proceed without connection

    try:
        # --- 2. Write Permission ---
        remote_dir = server["remote_dir"]
        check = ssh_exec(ssh, [
            f"mkdir -p {remote_dir} && touch {remote_dir}/.deploy_test && rm {remote_dir}/.deploy_test && echo 'WRITE_OK'"
        ])
        if check[0]["exit_code"] == 0 and "WRITE_OK" in check[0]["stdout"]:
            results["write_access"] = {"status": "ok", "detail": remote_dir}
        else:
            results["write_access"] = {"status": "fail", "detail": check[0]["stderr"] or "Cannot write to directory"}

        # --- 3. Python ---
        check = ssh_exec(ssh, ["python3 --version 2>&1"])
        if check[0]["exit_code"] == 0 and "Python" in check[0]["stdout"]:
            version = check[0]["stdout"].strip().split()[-1]
            results["python"] = {"status": "ok", "detail": version, "version": version}
        else:
            results["python"] = {"status": "missing", "detail": "python3 not found"}

        # --- 4. Node.js ---
        check = ssh_exec(ssh, ["node --version 2>&1"])
        if check[0]["exit_code"] == 0 and check[0]["stdout"].startswith("v"):
            version = check[0]["stdout"].strip()
            results["node"] = {"status": "ok", "detail": version, "version": version}
        else:
            results["node"] = {"status": "missing", "detail": "node not found"}

        # --- 5. Docker ---
        check = ssh_exec(ssh, ["docker --version 2>&1"])
        if check[0]["exit_code"] == 0 and "Docker" in check[0]["stdout"]:
            version = check[0]["stdout"].strip()
            results["docker"] = {"status": "ok", "detail": version}
            # Also check docker-compose / docker compose
            check2 = ssh_exec(ssh, ["docker compose version 2>&1 || docker-compose --version 2>&1"])
            results["docker_compose"] = {
                "status": "ok" if check2[0]["exit_code"] == 0 else "missing",
                "detail": check2[0]["stdout"].strip() or "not found",
            }
        else:
            results["docker"] = {"status": "missing", "detail": "docker not found"}
            results["docker_compose"] = {"status": "missing", "detail": "docker not found"}

        # --- 6. Nginx ---
        check = ssh_exec(ssh, ["nginx -v 2>&1"])
        if "nginx" in (check[0]["stdout"] + check[0]["stderr"]).lower():
            version_text = (check[0]["stderr"] or check[0]["stdout"]).strip()
            results["nginx"] = {"status": "ok", "detail": version_text}
        else:
            results["nginx"] = {"status": "missing", "detail": "nginx not found"}

        # --- 7. systemd ---
        check = ssh_exec(ssh, ["systemctl --version 2>&1 | head -1"])
        if check[0]["exit_code"] == 0 and "systemd" in check[0]["stdout"].lower():
            results["systemd"] = {"status": "ok", "detail": check[0]["stdout"].strip()}
        else:
            results["systemd"] = {"status": "missing", "detail": "systemd not available"}

        # --- 8. Disk Space ---
        check = ssh_exec(ssh, ["df -h / | tail -1 | awk '{print $4, $5}'"])
        if check[0]["exit_code"] == 0:
            parts = check[0]["stdout"].strip().split()
            free_space = parts[0] if parts else "unknown"
            use_pct = parts[1] if len(parts) > 1 else "unknown"
            # Warn if usage > 90% or free < 1G
            warn = False
            if use_pct != "unknown":
                try:
                    pct = int(use_pct.replace("%", ""))
                    warn = pct > 90
                except ValueError:
                    pass
            results["disk"] = {
                "status": "warn" if warn else "ok",
                "detail": f"{free_space} free ({use_pct} used)",
            }
        else:
            results["disk"] = {"status": "unknown", "detail": "Could not check disk space"}

        # --- 9. Memory ---
        check = ssh_exec(ssh, ["free -h | awk '/^Mem:/{print $2, $7}'"])
        if check[0]["exit_code"] == 0:
            parts = check[0]["stdout"].strip().split()
            total = parts[0] if parts else "unknown"
            available = parts[1] if len(parts) > 1 else "unknown"
            # Warn if available < 512M (rough heuristic)
            warn = False
            if available != "unknown":
                try:
                    val = float(available.replace("Gi", "").replace("Mi", "").replace("G", "").replace("M", ""))
                    if "M" in available and val < 512:
                        warn = True
                except ValueError:
                    pass
            results["memory"] = {
                "status": "warn" if warn else "ok",
                "detail": f"{total} total / {available} available",
            }
        else:
            results["memory"] = {"status": "unknown", "detail": "Could not check memory"}

        # --- 10. OS Info (bonus — useful for later phases) ---
        check = ssh_exec(ssh, ["cat /etc/os-release 2>/dev/null | head -4"])
        if check[0]["exit_code"] == 0:
            results["os_info"] = {"status": "ok", "detail": check[0]["stdout"].strip()}

    except Exception as e:
        # Connection may have dropped during checks
        results["_error"] = {"status": "fail", "detail": f"Check sequence interrupted: {e}"}

    return results, ssh  # Return ssh for connection reuse
```

#### Step 3.8: Pre-Flight Report

After running all checks, present the results in a clear visual format:

```
=== Pre-Flight Report ===

Server: prod-1 (deploy@10.0.1.10:22)
+-----------------+--------+----------------------------------+
| Check           | Status | Detail                           |
+-----------------+--------+----------------------------------+
| Connection      |   OK   | SSH connection established        |
| Write access    |   OK   | /opt/my-webapp                   |
| Python          |   OK   | 3.10.12                          |
| Node.js         |   OK   | v20.11.0                         |
| Docker          |   OK   | Docker version 24.0.7            |
| Docker Compose  |   OK   | v2.21.0                          |
| Nginx           |   OK   | nginx/1.24.0                     |
| systemd         |   OK   | systemd 252                      |
| Disk            |   OK   | 45G free (45% used)              |
| Memory          |  WARN  | 8.0Gi total / 450Mi available    |
+-----------------+--------+----------------------------------+

Warnings:
  - Memory: Low available memory (450Mi). Deployment may cause OOM.
    Consider freeing memory or using a smaller deployment config.
```

Status symbols used in the report:
- `OK` — check passed, component available
- `WARN` — check passed with caveats (low resources)
- `MISS` — optional component not installed
- `FAIL` — critical check failed, blocks deployment

#### Step 3.9: Pre-Flight Failure Handling

After the report, evaluate failures and handle each case:

**Critical failures (FAIL) — block deployment:**

| Check | Failure Action |
|-------|---------------|
| Connection | Cannot proceed. Present error details and ask user: |

```
AskUserQuestion:
  "SSH connection to {host}:{port} failed: {error_detail}.
   How would you like to proceed?"
  candidates:
    - "I'll fix the credentials / network — retry connection"
    - "Skip this server and continue with others"
    - "Abort deployment"
```

| Check | Failure Action |
|-------|---------------|
| Write access | Cannot deploy to this directory. Ask user: |

```
AskUserQuestion:
  "Cannot write to {remote_dir} on {host}: {error_detail}.
   How would you like to proceed?"
  candidates:
    - "Try a different directory (specify)"
    - "I'll fix permissions on the server — retry"
    - "Skip this server"
    - "Abort deployment"
```

**Missing components (MISS) — handled per deployment needs:**

The skill cross-references missing components against the `project_profile` and the user's chosen deployment mode:

```python
def evaluate_missing_components(preflight, project_profile, deploy_mode):
    """
    Determine which missing components are blockers vs. ignorable.
    Returns list of (component, severity, message) tuples.
    """
    issues = []

    # Python needed for Python backends
    if preflight.get("python", {}).get("status") == "missing":
        if project_profile.get("backend_type") in ("flask", "django", "fastapi"):
            issues.append(("python", "blocker",
                "Python 3 is required for your {backend_type} backend but is not installed."))
        else:
            issues.append(("python", "info", "Python 3 not found (not needed for this project)."))

    # Node needed for Node frontends/backends
    if preflight.get("node", {}).get("status") == "missing":
        if project_profile.get("frontend_type") or (project_profile.get("backend_type") in ("express", "nextjs")):
            issues.append(("node", "blocker",
                "Node.js is required for your project but is not installed."))
        else:
            issues.append(("node", "info", "Node.js not found (not needed for this project)."))

    # Docker needed only in docker deploy mode
    if preflight.get("docker", {}).get("status") == "missing":
        if deploy_mode == "docker":
            issues.append(("docker", "blocker",
                "Docker is required for Docker deployment mode but is not installed."))
        else:
            issues.append(("docker", "info", "Docker not found (not needed for systemd mode)."))

    # Nginx needed for reverse proxy
    if preflight.get("nginx", {}).get("status") == "missing":
        issues.append(("nginx", "warn",
            "Nginx not found. Reverse proxy configuration will be skipped."))

    # systemd needed for systemd deploy mode
    if preflight.get("systemd", {}).get("status") == "missing":
        if deploy_mode == "systemd":
            issues.append(("systemd", "blocker",
                "systemd is required for systemd deployment mode but is not available."))
        else:
            issues.append(("systemd", "info", "systemd not found (not needed for Docker mode)."))

    return issues
```

For each **blocker** issue, present an `AskUserQuestion`:

```
AskUserQuestion:
  "{component} is required but missing on {server_name}.
   How would you like to proceed?"
  candidates:
    - "Install {component} on the server (skill will run install commands)"
    - "Switch deployment mode (e.g., systemd <-> Docker)"
    - "Skip this server"
    - "Abort deployment"
```

If the user chooses to install, the skill runs the appropriate install command:

```python
INSTALL_COMMANDS = {
    "python": "sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv",
    "node": "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs",
    "docker": "curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker $USER",
    "nginx": "sudo apt-get update && sudo apt-get install -y nginx && sudo systemctl enable nginx",
}
```

After installation, re-run the specific check to verify success.

**Warning issues (WARN) — inform but continue:**

For resource warnings (disk, memory), display the warning in the report and continue. The user can choose to abort if they consider the risk too high.

```
AskUserQuestion:
  "Pre-flight checks completed with warnings (see report above).
   Continue with deployment?"
  candidates:
    - "Yes, continue deployment"
    - "No, I need to address the warnings first"
```

#### Step 3.10: Build Server Contexts

After all pre-flight checks pass (or warnings are accepted), build the final `server_contexts` list:

```python
server_contexts = []
for server, (preflight_results, ssh_conn) in zip(servers, preflight_data):
    ctx = {
        "name": server["name"],
        "host": server["host"],
        "port": server.get("port", 22),
        "user": server["user"],
        "key_path": server.get("key_path"),
        "remote_dir": server["remote_dir"],
        "ssh": ssh_conn,  # Reuse the connection from pre-flight
        "preflight": preflight_results,
        "per_server_config": server.get("config_overrides", {}),
    }
    server_contexts.append(ctx)
```

This `server_contexts` list is the primary output of Phase 3 and is consumed by all subsequent phases (4-8).

#### Step 3.11: Save Server Config to Memory (Optional)

After successful connection, offer to save server metadata (NOT credentials) to auto-memory:

```
AskUserQuestion:
  "Save server configuration to memory for future deployments?
   (Only connection metadata is saved — NEVER passwords or keys)"
  candidates:
    - "Yes, save to memory"
    - "No, don't save"
```

If saving, write a memory reference file with:
- Server name, host, port, username
- Key path (path only, not the key content)
- Remote directory
- OS info from pre-flight
- Pre-flight capability summary

---

### Security Rules

<IMPORTANT>
The following rules apply to ALL SSH/SFTP operations throughout the skill:

1. **NEVER store passwords** in any file — not in templates, configs, deploy-servers.json, memory, or SKILL output. Passwords are read ONLY from the `SSH_PASS` environment variable at runtime.
2. **NEVER echo or log passwords** in any command output, pre-flight report, or error message.
3. **NEVER commit credentials** — deploy-servers.json must NOT contain password fields. If a user's deploy-servers.json contains a `password` field, warn them and refuse to use it.
4. **Prefer SSH key authentication** over password auth. When asking the user, present key auth as the recommended option.
5. **Use environment variables** for all sensitive values: `SSH_PASS`, `DEPLOY_KEY`. The skill reads these at runtime.
6. **Memory saves metadata only** — host, username, key_path (the file path, not contents), remote_dir, and OS info. NEVER save passwords, tokens, or key file contents.
7. **Validate key file permissions** — if the SSH key file exists but has overly permissive permissions (e.g., 0644 on the local machine), warn the user. (On Windows, skip this check.)
8. **Connection timeout** — all SSH connections use a 15-second timeout. If the server doesn't respond within 15 seconds, treat it as unreachable.
</IMPORTANT>

---

### Multi-Server Orchestration

When deploying to multiple servers, the skill supports two execution strategies:

#### Sequential Mode (Default for First Deploy)

Used when deploying to servers for the first time or when the user hasn't deployed to these servers before.

**Execution flow:**

```
Server 1 → Deploy → Verify → [Pass?]
  │                              ├─ Yes → Server 2 → Deploy → Verify → ...
  │                              └─ No  → Ask User:
  │                                         - "Retry this server"
  │                                         - "Skip and continue to next server"
  │                                         - "Abort remaining servers"
```

In sequential mode:
1. Deploy to each server one at a time
2. Run verification after each server
3. If a server fails, pause and ask the user how to proceed
4. Report per-server status as each completes

```python
def deploy_sequential(server_contexts, deploy_fn, verify_fn):
    """
    Deploy to servers sequentially with per-server error handling.

    Args:
        server_contexts: list of server_context dicts
        deploy_fn: callable(ctx) -> bool (True = success)
        verify_fn: callable(ctx) -> bool (True = verified)

    Returns:
        list of {server, status, error} dicts
    """
    results = []
    for ctx in server_contexts:
        print(f"\n{'='*50}")
        print(f"Deploying to: {ctx['name']} ({ctx['host']})")
        print(f"{'='*50}")

        ssh = ensure_connected(ctx)
        try:
            success = deploy_fn(ctx)
            if success:
                verified = verify_fn(ctx)
                results.append({
                    "server": ctx["name"],
                    "status": "verified" if verified else "deployed_unverified",
                })
            else:
                results.append({
                    "server": ctx["name"],
                    "status": "failed",
                    "error": "Deployment failed",
                })
                # AskUserQuestion here: retry / skip / abort
        except Exception as e:
            results.append({
                "server": ctx["name"],
                "status": "error",
                "error": str(e),
            })
            # AskUserQuestion here: retry / skip / abort

    return results
```

#### Parallel Mode (For Redeploy)

Used when redeploying to multiple known-good servers (all servers have been successfully deployed to before).

**Execution flow:**

```
┌─── Agent: Server 1 → Deploy → Verify ───┐
├─── Agent: Server 2 → Deploy → Verify ───┤  → Collect Results → Report
└─── Agent: Server 3 → Deploy → Verify ───┘
```

In parallel mode, the skill uses the `Agent` tool to spawn one subagent per server. Each subagent receives:
- The SSH helper functions (from this section)
- The server's `server_context`
- The deployment commands to execute
- The verification checks to run

```python
# Parallel deployment uses Agent tool — each agent gets:
agent_prompt_template = """
You are deploying to server: {server_name} ({host}).

SSH Connection:
  host={host}, port={port}, user={user}, key_path={key_path}

Remote directory: {remote_dir}

{ssh_helper_functions}

Execute these deployment steps:
{deployment_steps}

Then run verification:
{verification_steps}

Report results as:
  SERVER: {server_name}
  STATUS: success | failed
  DETAILS: (any relevant output)
"""
```

**Parallel mode activation criteria:**
- User has selected "redeploy" (not first-time deploy)
- All servers passed pre-flight checks
- More than one server in the target list

```
AskUserQuestion:
  "Multiple servers configured. Deployment strategy?"
  candidates:
    - "Sequential (one at a time — safer, recommended for first deploy)"
    - "Parallel (all at once — faster, recommended for redeploy)"
```

#### Per-Server Configuration

Each server can have its own configuration overrides that supplement or replace the global template variables. These overrides are stored in `config_overrides` within `deploy-servers.json` or collected interactively.

```python
def resolve_server_config(global_config, server_ctx):
    """
    Merge global template variables with per-server overrides.
    Per-server values take precedence.

    Args:
        global_config: dict of template variables from project analysis
        server_ctx: server_context dict (includes per_server_config)

    Returns:
        dict of resolved template variables for this server
    """
    merged = dict(global_config)
    merged.update({
        "SERVER_HOST": server_ctx["host"],
        "SERVER_USER": server_ctx["user"],
        "REMOTE_DIR": server_ctx["remote_dir"],
        "SERVER_NAME": server_ctx["name"],
    })
    # Per-server overrides (domain, ports, SSL paths, etc.)
    merged.update(server_ctx.get("per_server_config", {}))
    return merged
```

Common per-server override fields:
- `NGINX_DOMAIN` — different domain per server (e.g., `app.example.com` vs `staging.example.com`)
- `BACKEND_PORT` — different port to avoid conflicts
- `FRONTEND_PORT` — different port to avoid conflicts
- `SSL_CERT_PATH` — server-specific SSL certificate location
- `SSL_KEY_PATH` — server-specific SSL key location
- `DEPLOY_ENV` — environment identifier (`production`, `staging`, `dev`)

---

### Phase 3 Outputs

Phase 3 produces the following data structures consumed by later phases:

| Output | Type | Consumed By |
|--------|------|------------|
| `server_contexts` | list[dict] | Phase 5 (template rendering), Phase 6 (deployment), Phase 7 (verification) |
| `server_contexts[].ssh` | paramiko.SSHClient | All remote operations in Phases 5-7 |
| `server_contexts[].preflight` | dict | Phase 4 (deployment plan — decides systemd vs docker based on available components) |
| `server_contexts[].per_server_config` | dict | Phase 5 (template variable resolution per server) |
| SSH helper functions | Python functions | All phases that perform remote operations |

### Phase 3 Exit Gate

Phase 3 is complete when ALL of the following are true:
1. At least one server has passed pre-flight checks (connection + write access at minimum)
2. All critical blockers have been resolved (by installation, mode switch, or server skip)
3. `server_contexts` list is built with active SSH connections
4. User has confirmed they want to proceed with the listed servers

After the gate is satisfied, proceed to **Phase 4: Deployment Plan Generation**.
