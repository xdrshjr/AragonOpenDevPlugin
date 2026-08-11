#!/usr/bin/env bash
# =============================================================================
# InkClaw — One-click systemd service installer
#
# Installs Flask backend + Next.js frontend as systemd services with optional
# watchdog timer and logrotate configuration.
#
# Usage: sudo ./ops/install.sh [--no-start] [--no-watchdog] [--no-logrotate]
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
# Argument parsing
# ---------------------------------------------------------------------------
NO_START=false
NO_WATCHDOG=false
NO_LOGROTATE=false
NO_NGINX=false

for arg in "$@"; do
  case "$arg" in
    --no-start)     NO_START=true ;;
    --no-watchdog)  NO_WATCHDOG=true ;;
    --no-logrotate) NO_LOGROTATE=true ;;
    --no-nginx)     NO_NGINX=true ;;
    --domain=*)     NGINX_DOMAIN_ARG="${arg#*=}" ;;
    --help|-h)
      echo "Usage: sudo $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --no-start       Install without starting services"
      echo "  --no-watchdog    Skip watchdog timer installation"
      echo "  --no-logrotate   Skip logrotate configuration"
      echo "  --no-nginx       Skip Nginx reverse proxy configuration"
      echo "  --domain=DOMAIN  Override NGINX_DOMAIN from config.env"
      echo "  --help, -h       Show this help message"
      exit 0
      ;;
    *) warn "Unknown argument: $arg" ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve script and project directories
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"

# ---------------------------------------------------------------------------
# Step 1: Prerequisites
# ---------------------------------------------------------------------------
log "Checking prerequisites..."

# Must run as root / under sudo
if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run with sudo. Usage: sudo $0"
fi

# Validate project directory
if [[ ! -f "$PROJECT_DIR/package.json" ]]; then
  die "package.json not found in $PROJECT_DIR. Are you in the project root?"
fi
if [[ ! -f "$PROJECT_DIR/backend/app.py" ]]; then
  die "backend/app.py not found. Project structure looks incomplete."
fi

# Resolve node binary — sudo resets PATH so nvm/user-installed node is invisible.
# IMPORTANT: User's node (nvm/conda) takes priority over system /usr/bin/node
# because npm install/rebuild uses the user's node, and native modules (like
# better-sqlite3) are ABI-bound to the specific Node.js version.
resolve_node() {
  # 1. Explicit override from config.env (loaded later, but NODE_BIN env var works)
  if [[ -n "${NODE_BIN:-}" && -x "${NODE_BIN}" ]]; then
    echo "$NODE_BIN"; return 0
  fi

  # 2. Ask the original user's interactive login shell (nvm/conda/pyenv)
  #    This MUST come before system PATH to match the node used for npm install.
  if [[ -n "${SUDO_USER:-}" ]]; then
    local user_node
    user_node="$(sudo -u "$SUDO_USER" bash -ilc 'command -v node' 2>/dev/null)" || true
    if [[ -n "$user_node" && -x "$user_node" ]]; then
      echo "$user_node"; return 0
    fi
  fi

  # 3. Scan nvm directories (latest version first)
  if [[ -n "${SUDO_USER:-}" ]]; then
    local user_home
    user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    local candidate
    for candidate in $(ls -rd "$user_home"/.nvm/versions/node/*/bin/node 2>/dev/null); do
      if [[ -x "$candidate" ]]; then
        echo "$candidate"; return 0
      fi
    done
  fi

  # 4. Already in current (sudo) PATH — last resort, may be old system node
  command -v node 2>/dev/null && return 0

  # 5. Scan common system locations
  local candidate
  for candidate in \
    /usr/local/bin/node \
    /usr/bin/node \
    /snap/bin/node; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"; return 0
    fi
  done

  return 1
}

DETECTED_NODE="$(resolve_node)" || die "Node.js is not installed. Install it or set NODE_BIN in config.env."
# Add node's directory to PATH so npm etc. are also available
PATH="$(dirname "$DETECTED_NODE"):$PATH"
export PATH

# Check other required tools
command -v python3 >/dev/null 2>&1 || die "Python 3 is not installed."
command -v curl    >/dev/null 2>&1 || die "curl is not installed."

# Check build artifacts (distDir is 'out' per next.config.ts)
if [[ ! -d "$PROJECT_DIR/out" ]]; then
  die "out/ directory not found. Run 'npm run build' or deployment.sh first."
fi
if [[ ! -d "$PROJECT_DIR/backend/.venv" ]]; then
  die "backend/.venv/ not found. Create it with: python3 -m venv backend/.venv"
fi

ok "All prerequisites satisfied."

# ---------------------------------------------------------------------------
# Step 2: Detect runtime environment
# ---------------------------------------------------------------------------
log "Detecting runtime environment..."

if [[ -n "${SUDO_USER:-}" ]]; then
  RUN_USER="$SUDO_USER"
else
  RUN_USER="$USER"
fi
RUN_GROUP="$(id -gn "$RUN_USER")"

VENV_PYTHON="$PROJECT_DIR/backend/.venv/bin/python"
if [[ ! -x "$VENV_PYTHON" ]]; then
  die "Python venv binary not found at $VENV_PYTHON"
fi

NODE_BIN="$DETECTED_NODE"
USER_DATA_DIR="${USER_DATA_DIR:-/home/$RUN_USER/.inkclaw-data}"

# Build PATH for systemd services — must include node, python venv, and
# system tools like Xvfb/x11vnc/websockify that the app needs at runtime.
# Get the deploy user's full login PATH for conda/nvm/pyenv tools.
USER_LOGIN_PATH="$(sudo -u "$RUN_USER" bash -ilc 'echo $PATH' 2>/dev/null)" || true
PATH_DIRS="${USER_LOGIN_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
# Ensure node and venv dirs are included
PATH_DIRS="$(dirname "$NODE_BIN"):$(dirname "$VENV_PYTHON"):$PATH_DIRS"

ok "User=$RUN_USER  Group=$RUN_GROUP"
ok "Project=$PROJECT_DIR"
ok "Python=$VENV_PYTHON"
ok "Node=$NODE_BIN"
ok "UserData=$USER_DATA_DIR"

# ---------------------------------------------------------------------------
# Step 3: Load configuration
# ---------------------------------------------------------------------------
CONFIG_FILE="$SCRIPT_DIR/config.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
  die "Configuration file not found: $CONFIG_FILE"
fi
# shellcheck source=config.env
source "$CONFIG_FILE"
ok "Configuration loaded from $CONFIG_FILE"

# ---------------------------------------------------------------------------
# Step 4: Stop existing services (idempotent)
# ---------------------------------------------------------------------------
log "Stopping existing InkClaw services (if any)..."
systemctl stop inkclaw-watchdog.timer   2>/dev/null || true
systemctl stop inkclaw-watchdog.service 2>/dev/null || true
systemctl stop inkclaw-frontend.service 2>/dev/null || true
systemctl stop inkclaw-backend.service  2>/dev/null || true
systemctl disable inkclaw-watchdog.timer   2>/dev/null || true
systemctl disable inkclaw-frontend.service 2>/dev/null || true
systemctl disable inkclaw-backend.service  2>/dev/null || true
ok "Existing services stopped and disabled."

# ---------------------------------------------------------------------------
# Step 5: Install systemd unit files via template substitution
# ---------------------------------------------------------------------------
log "Installing systemd unit files..."

# Template substitution function
install_template() {
  local src="$1"
  local dest="$2"

  if [[ ! -f "$src" ]]; then
    die "Template not found: $src"
  fi

  sed \
    -e "s|{{PROJECT_DIR}}|${PROJECT_DIR}|g" \
    -e "s|{{RUN_USER}}|${RUN_USER}|g" \
    -e "s|{{RUN_GROUP}}|${RUN_GROUP}|g" \
    -e "s|{{VENV_PYTHON}}|${VENV_PYTHON}|g" \
    -e "s|{{NODE_BIN}}|${NODE_BIN}|g" \
    -e "s|{{BACKEND_PORT}}|${BACKEND_PORT}|g" \
    -e "s|{{FRONTEND_PORT}}|${FRONTEND_PORT}|g" \
    -e "s|{{USER_DATA_DIR}}|${USER_DATA_DIR}|g" \
    -e "s|{{WATCHDOG_INTERVAL}}|${WATCHDOG_INTERVAL}|g" \
    -e "s|{{PATH_DIRS}}|${PATH_DIRS}|g" \
    "$src" > "$dest"

  ok "Installed: $dest"
}

install_template "$TEMPLATE_DIR/inkclaw-backend.service" \
  "/etc/systemd/system/inkclaw-backend.service"

install_template "$TEMPLATE_DIR/inkclaw-frontend.service" \
  "/etc/systemd/system/inkclaw-frontend.service"

# ---------------------------------------------------------------------------
# Step 6: Install watchdog (unless --no-watchdog)
# ---------------------------------------------------------------------------
if [[ "$NO_WATCHDOG" == false ]]; then
  log "Installing watchdog service and timer..."

  install_template "$TEMPLATE_DIR/inkclaw-watchdog.service" \
    "/etc/systemd/system/inkclaw-watchdog.service"

  install_template "$TEMPLATE_DIR/inkclaw-watchdog.timer" \
    "/etc/systemd/system/inkclaw-watchdog.timer"

  # Ensure healthcheck.sh is executable
  chmod +x "$SCRIPT_DIR/healthcheck.sh"
  ok "Watchdog installed."
else
  warn "Skipping watchdog installation (--no-watchdog)."
fi

# ---------------------------------------------------------------------------
# Step 7: Install logrotate configuration (unless --no-logrotate)
# ---------------------------------------------------------------------------
if [[ "$NO_LOGROTATE" == false ]]; then
  log "Installing logrotate configuration..."

  if [[ -f "$TEMPLATE_DIR/inkclaw-logrotate" ]]; then
    sed \
      -e "s|{{PROJECT_DIR}}|${PROJECT_DIR}|g" \
      -e "s|{{LOG_DIR}}|${LOG_DIR}|g" \
      -e "s|{{LOG_MAX_SIZE}}|${LOG_MAX_SIZE}|g" \
      -e "s|{{LOG_ROTATE_COUNT}}|${LOG_ROTATE_COUNT}|g" \
      -e "s|{{RUN_USER}}|${RUN_USER}|g" \
      -e "s|{{RUN_GROUP}}|${RUN_GROUP}|g" \
      "$TEMPLATE_DIR/inkclaw-logrotate" > "/etc/logrotate.d/inkclaw"
    ok "Logrotate config installed to /etc/logrotate.d/inkclaw"
  else
    warn "Logrotate template not found at $TEMPLATE_DIR/inkclaw-logrotate, skipping."
  fi
else
  warn "Skipping logrotate installation (--no-logrotate)."
fi

# ---------------------------------------------------------------------------
# Step 8: Configure Nginx reverse proxy (unless --no-nginx)
# ---------------------------------------------------------------------------
configure_nginx() {
  if [[ "$NO_NGINX" == true ]]; then
    warn "Skipping Nginx configuration (--no-nginx)."
    return 0
  fi

  # --domain=X overrides config.env
  local domain="${NGINX_DOMAIN_ARG:-${NGINX_DOMAIN:-}}"
  local site_name="${NGINX_SITE_NAME:-inkclaw}"
  local nginx_conf="/etc/nginx/sites-available/$site_name"
  local nginx_enabled="/etc/nginx/sites-enabled/$site_name"

  if ! command -v nginx >/dev/null 2>&1; then
    warn "Nginx is not installed. Skipping reverse proxy configuration."
    warn "Agent SSE streams may fail without proper proxy settings."
    return 0
  fi

  # Auto-detect domain from existing config if not specified
  if [[ -z "$domain" && -f "$nginx_conf" ]]; then
    domain=$(grep -oP 'server_name\s+\K[^;]+' "$nginx_conf" 2>/dev/null | head -1 | xargs) || true
  fi

  if [[ -z "$domain" ]]; then
    warn "NGINX_DOMAIN not set in config.env and no existing config found."
    warn "Skipping Nginx setup. Set NGINX_DOMAIN or use --domain=YOUR_DOMAIN."
    return 0
  fi

  # Check if existing config already has SSE streaming settings (version marker)
  if [[ -f "$nginx_conf" ]]; then
    if grep -q "# InkClaw nginx config v1" "$nginx_conf"; then
      ok "Nginx config already has InkClaw SSE/streaming settings (v1). Skipping."
      return 0
    fi
    # Backup existing config
    cp "$nginx_conf" "${nginx_conf}.bak.$(date '+%Y%m%d%H%M%S')"
    log "Backed up existing Nginx config."
  fi

  log "Configuring Nginx reverse proxy for ${BOLD}${domain}${RESET}..."

  # Detect SSL certificates
  local primary_domain
  primary_domain=$(echo "$domain" | awk '{print $1}')
  local ssl_cert="" ssl_key="" ssl_extra=""

  if [[ -f "/etc/letsencrypt/live/${primary_domain}/fullchain.pem" ]]; then
    ssl_cert="/etc/letsencrypt/live/${primary_domain}/fullchain.pem"
    ssl_key="/etc/letsencrypt/live/${primary_domain}/privkey.pem"
    if [[ -f "/etc/letsencrypt/options-ssl-nginx.conf" ]]; then
      ssl_extra="    include /etc/letsencrypt/options-ssl-nginx.conf;"$'\n'
    fi
    if [[ -f "/etc/letsencrypt/ssl-dhparams.pem" ]]; then
      ssl_extra="${ssl_extra}    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"$'\n'
    fi
    ok "Detected Let's Encrypt SSL for ${primary_domain}."
  elif [[ -f "$nginx_conf" ]]; then
    ssl_cert=$(grep -oP 'ssl_certificate\s+\K[^;]+' "$nginx_conf" 2>/dev/null | head -1 | xargs) || true
    ssl_key=$(grep -oP 'ssl_certificate_key\s+\K[^;]+' "$nginx_conf" 2>/dev/null | head -1 | xargs) || true
  fi

  # Choose template and render
  local template
  if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
    template="$TEMPLATE_DIR/inkclaw-nginx"
  else
    template="$TEMPLATE_DIR/inkclaw-nginx-http"
    warn "No SSL certificate found. Using HTTP-only config."
    warn "Run: sudo certbot --nginx -d ${primary_domain} to enable HTTPS."
  fi

  if [[ ! -f "$template" ]]; then
    warn "Nginx template not found at $template. Skipping."
    return 0
  fi

  # Render template: use sed for single-line placeholders, bash for multi-line ssl_extra
  local rendered
  rendered=$(sed \
    -e "s|{{NGINX_DOMAIN}}|${domain}|g" \
    -e "s|{{FRONTEND_PORT}}|${FRONTEND_PORT}|g" \
    -e "s|{{NGINX_SSL_CERT}}|${ssl_cert}|g" \
    -e "s|{{NGINX_SSL_KEY}}|${ssl_key}|g" \
    "$template")

  # Replace multi-line ssl_extra using bash (sed breaks on embedded newlines)
  if [[ -n "$ssl_extra" ]]; then
    rendered="${rendered//\{\{NGINX_SSL_EXTRA\}\}/${ssl_extra}}"
  else
    rendered=$(printf '%s' "$rendered" | sed '/{{NGINX_SSL_EXTRA}}/d')
  fi

  printf '%s\n' "$rendered" > "$nginx_conf"

  # Create symlink if not already enabled
  if [[ ! -e "$nginx_enabled" ]]; then
    ln -s "$nginx_conf" "$nginx_enabled"
  fi

  # Clean duplicate domain blocks from the default site
  local default_conf="/etc/nginx/sites-enabled/default"
  if [[ -f "$default_conf" ]] && grep -q "$primary_domain" "$default_conf" 2>/dev/null; then
    warn "Removing duplicate ${primary_domain} blocks from default site..."
    cp "$default_conf" "${default_conf}.bak.$(date '+%Y%m%d%H%M%S')"
    local tmp_clean
    tmp_clean=$(mktemp)
    awk -v domain="$primary_domain" '
      /^server[ \t]*\{/ { block=""; depth=0; in_block=1 }
      in_block { block = block $0 "\n"; depth += gsub(/{/, "{"); depth -= gsub(/}/, "}"); if (depth<=0) { if (block !~ domain) printf "%s", block; in_block=0; block="" } next }
      { print }
    ' "$default_conf" > "$tmp_clean" && mv "$tmp_clean" "$default_conf"
  fi

  # Remove stale .bak files from sites-enabled (nginx glob includes them)
  find /etc/nginx/sites-enabled/ -name "*.bak*" -delete 2>/dev/null || true

  # Test and reload
  if nginx -t 2>&1; then
    systemctl reload nginx
    ok "Nginx configured and reloaded for ${BOLD}${domain}${RESET}."
  else
    error "Nginx config test failed! Check: nginx -t"
    local latest_backup
    latest_backup=$(ls -t "${nginx_conf}.bak."* 2>/dev/null | head -1) || true
    if [[ -n "$latest_backup" ]]; then
      cp "$latest_backup" "$nginx_conf"
      nginx -t 2>/dev/null && systemctl reload nginx && warn "Restored previous Nginx config."
    fi
  fi
}

configure_nginx

# ---------------------------------------------------------------------------
# Step 9: Reload systemd and enable services
# ---------------------------------------------------------------------------
log "Reloading systemd daemon..."
systemctl daemon-reload
ok "systemd daemon reloaded."

log "Enabling services..."
systemctl enable inkclaw-backend.service
systemctl enable inkclaw-frontend.service
if [[ "$NO_WATCHDOG" == false ]]; then
  systemctl enable inkclaw-watchdog.timer
fi
ok "Services enabled for boot."

# ---------------------------------------------------------------------------
# Step 10: Start services (unless --no-start)
# ---------------------------------------------------------------------------
if [[ "$NO_START" == false ]]; then
  log "Starting InkClaw backend..."
  systemctl start inkclaw-backend.service

  # Wait for backend to be ready (up to 30s)
  log "Waiting for backend to be ready..."
  BACKEND_READY=false
  for _ in $(seq 1 30); do
    if curl -sf "http://localhost:${BACKEND_PORT}/health" >/dev/null 2>&1 || \
       curl -sf "http://localhost:${BACKEND_PORT}/" >/dev/null 2>&1; then
      BACKEND_READY=true
      break
    fi
    sleep 1
  done
  if [[ "$BACKEND_READY" == true ]]; then
    ok "Backend is ready at http://localhost:${BACKEND_PORT}"
  else
    warn "Backend did not respond within 30s. Check: journalctl -u inkclaw-backend -f"
  fi

  log "Starting InkClaw frontend..."
  systemctl start inkclaw-frontend.service

  # Wait for frontend to be ready (up to 30s)
  log "Waiting for frontend to be ready..."
  FRONTEND_READY=false
  for _ in $(seq 1 30); do
    if curl -sf "http://localhost:${FRONTEND_PORT}/" >/dev/null 2>&1; then
      FRONTEND_READY=true
      break
    fi
    sleep 1
  done
  if [[ "$FRONTEND_READY" == true ]]; then
    ok "Frontend is ready at http://localhost:${FRONTEND_PORT}"
  else
    warn "Frontend did not respond within 30s. Check: journalctl -u inkclaw-frontend -f"
  fi

  if [[ "$NO_WATCHDOG" == false ]]; then
    log "Starting watchdog timer..."
    systemctl start inkclaw-watchdog.timer
    ok "Watchdog timer started."
  fi
else
  warn "Skipping service start (--no-start). Start manually with:"
  warn "  systemctl start inkclaw-backend inkclaw-frontend inkclaw-watchdog.timer"
fi

# ---------------------------------------------------------------------------
# Step 11: Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  InkClaw systemd installation complete${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo -e "  Backend  :  inkclaw-backend.service  (port ${CYAN}${BACKEND_PORT}${RESET})"
echo -e "  Frontend :  inkclaw-frontend.service (port ${CYAN}${FRONTEND_PORT}${RESET})"
if [[ "$NO_WATCHDOG" == false ]]; then
  echo -e "  Watchdog :  inkclaw-watchdog.timer   (every ${CYAN}${WATCHDOG_INTERVAL}s${RESET})"
fi
NGINX_SHOW_DOMAIN="${NGINX_DOMAIN_ARG:-${NGINX_DOMAIN:-}}"
if [[ -n "$NGINX_SHOW_DOMAIN" && "$NO_NGINX" == false ]]; then
  echo -e "  Nginx    :  ${CYAN}${NGINX_SHOW_DOMAIN}${RESET}  (reverse proxy with SSE support)"
fi
echo -e ""
echo -e "  ${BOLD}Useful commands:${RESET}"
echo -e "    systemctl status inkclaw-backend"
echo -e "    systemctl status inkclaw-frontend"
echo -e "    journalctl -u inkclaw-backend -f"
echo -e "    journalctl -u inkclaw-frontend -f"
echo -e "    sudo ./ops/uninstall.sh"
echo -e "${BOLD}============================================================${RESET}"
echo ""
