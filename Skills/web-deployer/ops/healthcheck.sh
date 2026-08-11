#!/usr/bin/env bash
# =============================================================================
# InkClaw — Watchdog health check script
#
# Checks HTTP liveness of Flask backend and Next.js frontend. Restarts the
# corresponding systemd service after WATCHDOG_FAIL_THRESHOLD consecutive
# failures. Triggered by inkclaw-watchdog.timer.
#
# Usage: ./ops/healthcheck.sh  (normally invoked by systemd, not manually)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck source=config.env
source "$CONFIG_FILE"

# Apply defaults for any missing config values
BACKEND_PORT="${BACKEND_PORT:-5000}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
WATCHDOG_FAIL_THRESHOLD="${WATCHDOG_FAIL_THRESHOLD:-3}"
WATCHDOG_STATE_DIR="${WATCHDOG_STATE_DIR:-/tmp}"

# ---------------------------------------------------------------------------
# Logging — writes to syslog via logger and stdout (captured by journal)
# ---------------------------------------------------------------------------
log() {
  logger -t inkclaw-watchdog "$*"
  echo "$*"
}

# ---------------------------------------------------------------------------
# Concurrency protection via flock
# ---------------------------------------------------------------------------
LOCK_FILE="$WATCHDOG_STATE_DIR/inkclaw-watchdog.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "Another healthcheck is running, skipping."
  exit 0
fi

# ---------------------------------------------------------------------------
# Health check function
#
# Arguments:
#   $1 — service name (e.g., "backend", "frontend")
#   $2 — port number
#   $3 — systemd unit name (e.g., "inkclaw-backend.service")
# ---------------------------------------------------------------------------
check_service() {
  local name="$1"
  local port="$2"
  local unit="$3"
  local fail_file="$WATCHDOG_STATE_DIR/inkclaw-watchdog-${name}-failures"
  local url="http://localhost:${port}/health"
  local fallback_url="http://localhost:${port}/"
  local http_code

  # Attempt primary health endpoint, fall back to root.
  # Use a generous timeout (30s) because the frontend may be under heavy load
  # when agent tasks are running (e.g., pip install, large LLM calls).
  http_code=$(curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 30 "$url" 2>/dev/null) || true

  if ! [[ "$http_code" =~ ^2 ]]; then
    # Try fallback URL
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 30 "$fallback_url" 2>/dev/null) || true
  fi

  if [[ "$http_code" =~ ^2 ]]; then
    # Success — reset failure counter
    echo "0" > "$fail_file"
    log "[OK] ${name} is healthy (http://localhost:${port})"
    return 0
  fi

  # HTTP check failed — but if the process is still running and listening on the
  # port, it may just be temporarily overloaded by a long agent task. Only count
  # the failure if the port is not being listened on (process truly dead/hung).
  if ss -tlnH sport = :"$port" 2>/dev/null | grep -q .; then
    log "[WARN] ${name} HTTP check failed but port :${port} is listening — process may be busy, not counting as failure"
    return 0
  fi

  # Failure — increment counter
  local current_failures=0
  if [[ -f "$fail_file" ]]; then
    current_failures=$(cat "$fail_file" 2>/dev/null) || true
    # Validate that the value is a number
    if ! [[ "$current_failures" =~ ^[0-9]+$ ]]; then
      current_failures=0
    fi
  fi
  current_failures=$((current_failures + 1))
  echo "$current_failures" > "$fail_file"

  log "[FAIL] ${name} check failed (attempt ${current_failures}/${WATCHDOG_FAIL_THRESHOLD})"

  if [[ "$current_failures" -ge "$WATCHDOG_FAIL_THRESHOLD" ]]; then
    log "[RESTART] ${name} — restarting after ${WATCHDOG_FAIL_THRESHOLD} consecutive failures"
    if systemctl restart "$unit" 2>/dev/null; then
      log "[OK] ${name} restarted successfully"
    else
      log "[ERROR] ${name} restart failed"
    fi
    # Reset counter after restart attempt
    echo "0" > "$fail_file"
  fi
}

# ---------------------------------------------------------------------------
# Run health checks
# ---------------------------------------------------------------------------
check_service "backend"  "$BACKEND_PORT"  "inkclaw-backend.service"
check_service "frontend" "$FRONTEND_PORT" "inkclaw-frontend.service"
