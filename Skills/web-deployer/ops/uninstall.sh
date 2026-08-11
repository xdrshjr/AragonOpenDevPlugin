#!/usr/bin/env bash
# =============================================================================
# InkClaw — Uninstall systemd services
#
# Stops and removes all InkClaw systemd services, watchdog timer, and logrotate
# configuration. Does NOT delete project files, logs, or user data.
#
# Usage: sudo ./ops/uninstall.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (consistent with deployment.sh)
# ---------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()   { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*"; }
ok()    { echo -e "${GREEN}[$(date '+%H:%M:%S')] OK${RESET} $*"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN${RESET} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR${RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Step 1: Check sudo
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run with sudo. Usage: sudo $0"
fi

# ---------------------------------------------------------------------------
# Load configuration (for WATCHDOG_STATE_DIR)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=config.env
  source "$CONFIG_FILE"
fi
WATCHDOG_STATE_DIR="${WATCHDOG_STATE_DIR:-/tmp}"

echo ""
log "Uninstalling InkClaw systemd services..."

# ---------------------------------------------------------------------------
# Step 2: Stop services
# ---------------------------------------------------------------------------
log "Stopping services..."
systemctl stop inkclaw-watchdog.timer   2>/dev/null || true
systemctl stop inkclaw-watchdog.service 2>/dev/null || true
systemctl stop inkclaw-frontend.service 2>/dev/null || true
systemctl stop inkclaw-backend.service  2>/dev/null || true
ok "Services stopped."

# ---------------------------------------------------------------------------
# Step 3: Disable services
# ---------------------------------------------------------------------------
log "Disabling services..."
systemctl disable inkclaw-watchdog.timer   2>/dev/null || true
systemctl disable inkclaw-frontend.service 2>/dev/null || true
systemctl disable inkclaw-backend.service  2>/dev/null || true
ok "Services disabled."

# ---------------------------------------------------------------------------
# Step 4: Remove unit files, logrotate config, and state files
# ---------------------------------------------------------------------------
log "Removing systemd unit files..."
rm -f /etc/systemd/system/inkclaw-backend.service
rm -f /etc/systemd/system/inkclaw-frontend.service
rm -f /etc/systemd/system/inkclaw-watchdog.service
rm -f /etc/systemd/system/inkclaw-watchdog.timer
ok "Unit files removed."

log "Removing logrotate configuration..."
rm -f /etc/logrotate.d/inkclaw
ok "Logrotate config removed."

log "Removing watchdog state files..."
rm -f "$WATCHDOG_STATE_DIR/inkclaw-watchdog-backend-failures"
rm -f "$WATCHDOG_STATE_DIR/inkclaw-watchdog-frontend-failures"
rm -f "$WATCHDOG_STATE_DIR/inkclaw-watchdog.lock"
ok "Watchdog state files removed."

NGINX_SITE_NAME="${NGINX_SITE_NAME:-inkclaw}"
if [[ -e "/etc/nginx/sites-enabled/$NGINX_SITE_NAME" || -e "/etc/nginx/sites-available/$NGINX_SITE_NAME" ]]; then
  log "Removing Nginx reverse proxy configuration..."
  rm -f "/etc/nginx/sites-enabled/$NGINX_SITE_NAME"
  rm -f "/etc/nginx/sites-available/$NGINX_SITE_NAME"
  rm -f /etc/nginx/sites-available/${NGINX_SITE_NAME}.bak.* 2>/dev/null || true
  if command -v nginx >/dev/null 2>&1 && nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || true
  fi
  ok "Nginx config removed."
else
  ok "No Nginx config found — skipping."
fi

# ---------------------------------------------------------------------------
# Step 5: Reload systemd
# ---------------------------------------------------------------------------
log "Reloading systemd daemon..."
systemctl daemon-reload
ok "systemd daemon reloaded."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  InkClaw systemd services uninstalled${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo -e "  ${YELLOW}Note:${RESET} Project files, logs, and user data were NOT deleted."
echo -e "  To remove them manually:"
echo -e "    rm -rf <project-dir>/logs/"
echo -e "    rm -rf ~/.inkclaw-data/"
echo -e "${BOLD}============================================================${RESET}"
echo ""
