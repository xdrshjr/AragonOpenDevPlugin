#!/usr/bin/env bash
# =============================================================================
# InkClaw — Dependency installer
#
# Installs all project dependencies in the current environment:
#   1. Python packages (pip, into current conda/venv)
#   2. Node.js packages (npm install)
#   3. Playwright Chromium browser + system deps
#   4. VNC dependencies (Xvfb, x11vnc, websockify)
#
# Designed to work with conda, venv, or system Python — uses whatever
# python/pip/node are in the current PATH.
#
# Usage:
#   ./ops/install-deps.sh                 # install everything
#   ./ops/install-deps.sh --skip-system   # skip apt packages (no sudo needed)
#   ./ops/install-deps.sh --only python   # only Python deps
#   ./ops/install-deps.sh --only node     # only Node.js deps
#   ./ops/install-deps.sh --only playwright  # only Playwright
#   ./ops/install-deps.sh --only vnc      # only VNC deps
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

log()   { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*"; }
ok()    { echo -e "${GREEN}[$(date '+%H:%M:%S')] OK${RESET} $*"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN${RESET} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR${RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SKIP_SYSTEM=false
ONLY=""

for arg in "$@"; do
  case "$arg" in
    --skip-system|-s) SKIP_SYSTEM=true ;;
    --only)           ;; # value handled below
    python|node|playwright|vnc)
      ONLY="$arg" ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --skip-system, -s   Skip system packages (no sudo required)"
      echo "  --only <component>  Install only: python, node, playwright, vnc"
      echo "  --help, -h          Show this help"
      exit 0
      ;;
    *) warn "Unknown argument: $arg" ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve project directory
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$PROJECT_DIR/backend"

# Validate project
if [[ ! -f "$PROJECT_DIR/package.json" ]]; then
  die "package.json not found in $PROJECT_DIR. Are you in the project root?"
fi

# ---------------------------------------------------------------------------
# Detect available tools
# ---------------------------------------------------------------------------
log "Detecting environment..."

HAVE_PYTHON=false
HAVE_PIP=false
HAVE_NODE=false
HAVE_NPM=false
HAVE_NPX=false
HAVE_SUDO=false

command -v python3 >/dev/null 2>&1 && HAVE_PYTHON=true || true
command -v pip     >/dev/null 2>&1 && HAVE_PIP=true || \
  { command -v pip3 >/dev/null 2>&1 && HAVE_PIP=true; } || true
command -v node    >/dev/null 2>&1 && HAVE_NODE=true  || true
command -v npm     >/dev/null 2>&1 && HAVE_NPM=true   || true
command -v npx     >/dev/null 2>&1 && HAVE_NPX=true   || true
sudo -n true 2>/dev/null          && HAVE_SUDO=true || true

# Determine pip command
PIP_CMD=""
if command -v pip >/dev/null 2>&1; then
  PIP_CMD="pip"
elif command -v pip3 >/dev/null 2>&1; then
  PIP_CMD="pip3"
fi

# Show environment info
PYTHON_INFO=""
if [[ "$HAVE_PYTHON" == true ]]; then
  PYTHON_INFO="$(python3 --version) @ $(command -v python3)"
fi
NODE_INFO=""
if [[ "$HAVE_NODE" == true ]]; then
  NODE_INFO="$(node --version) @ $(command -v node)"
fi
CONDA_INFO="${CONDA_DEFAULT_ENV:-none}"

echo -e "  Python:  ${CYAN}${PYTHON_INFO:-not found}${RESET}"
echo -e "  Node.js: ${CYAN}${NODE_INFO:-not found}${RESET}"
echo -e "  Conda:   ${CYAN}${CONDA_INFO}${RESET}"
echo -e "  sudo:    ${CYAN}${HAVE_SUDO}${RESET}"
echo ""

# Helper: should we run this component?
should_run() {
  [[ -z "$ONLY" || "$ONLY" == "$1" ]]
}

ERRORS=0
# Note: ((ERRORS++)) when ERRORS=0 returns exit code 1 (falsy), which triggers
# set -e. We use ERRORS=$((ERRORS + 1)) instead to avoid this pitfall.

# ---------------------------------------------------------------------------
# 1. Python dependencies
# ---------------------------------------------------------------------------
if should_run python; then
  log "${BOLD}[1/4] Python dependencies${RESET}"

  if [[ "$HAVE_PYTHON" == false ]]; then
    error "Python 3 not found. Install Python 3.8+ first."
    ERRORS=$((ERRORS + 1))
  elif [[ -z "$PIP_CMD" ]]; then
    error "pip not found. Install pip: python3 -m ensurepip --upgrade"
    ERRORS=$((ERRORS + 1))
  else
    # Upgrade pip
    log "Upgrading pip..."
    "$PIP_CMD" install --upgrade pip --quiet 2>&1 | tail -2 || true

    # Install backend requirements
    if [[ -f "$BACKEND_DIR/requirements.txt" ]]; then
      log "Installing Python packages from requirements.txt..."
      "$PIP_CMD" install -r "$BACKEND_DIR/requirements.txt" --quiet
      ok "Python packages installed."
    else
      warn "backend/requirements.txt not found, skipping."
    fi
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# 2. Node.js dependencies
# ---------------------------------------------------------------------------
if should_run node; then
  log "${BOLD}[2/4] Node.js dependencies${RESET}"

  if [[ "$HAVE_NODE" == false || "$HAVE_NPM" == false ]]; then
    error "Node.js or npm not found. Install Node.js 18+ first."
    ERRORS=$((ERRORS + 1))
  else
    log "Installing Node.js packages..."
    cd "$PROJECT_DIR"
    npm install --loglevel=error
    # Rebuild native addons (better-sqlite3 etc.) for the current Node.js version
    log "Rebuilding native modules..."
    npm rebuild 2>&1 | tail -5
    ok "Node.js packages installed and native modules rebuilt."
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# 3. Playwright browser
# ---------------------------------------------------------------------------
if should_run playwright; then
  log "${BOLD}[3/4] Playwright Chromium browser${RESET}"

  if [[ "$HAVE_NPX" == false ]]; then
    error "npx not found. Install Node.js 18+ first."
    ERRORS=$((ERRORS + 1))
  else
    # Install Chromium browser binary
    log "Installing Playwright Chromium..."
    cd "$PROJECT_DIR"
    npx playwright install chromium 2>&1 | tail -5 || {
      error "Playwright Chromium install failed."
      ERRORS=$((ERRORS + 1))
    }

    # Install system-level dependencies (needs sudo)
    if [[ "$SKIP_SYSTEM" == false && "$HAVE_SUDO" == true ]]; then
      log "Installing Playwright system dependencies (requires sudo)..."
      npx playwright install-deps chromium 2>&1 | tail -5 || {
        warn "Playwright system deps failed. Try: sudo npx playwright install-deps chromium"
      }
    elif [[ "$SKIP_SYSTEM" == true ]]; then
      warn "Skipping system deps (--skip-system). Run manually if needed: sudo npx playwright install-deps chromium"
    else
      warn "No sudo access. System deps skipped. Run manually: sudo npx playwright install-deps chromium"
    fi
    ok "Playwright setup complete."
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# 4. VNC dependencies (Xvfb, x11vnc, websockify)
# ---------------------------------------------------------------------------
if should_run vnc; then
  log "${BOLD}[4/4] VNC dependencies${RESET}"

  # System packages: xvfb, x11vnc, novnc (websockify needs --web /usr/share/novnc)
  if [[ "$SKIP_SYSTEM" == false ]]; then
    if [[ "$HAVE_SUDO" == true ]] && command -v apt-get >/dev/null 2>&1; then
      log "Installing Xvfb, x11vnc, and noVNC via apt..."
      sudo apt-get update -qq
      sudo apt-get install -y -qq xvfb x11vnc novnc 2>/dev/null || {
        warn "Failed to install xvfb/x11vnc/novnc. VNC features will be unavailable."
      }
      ok "Xvfb, x11vnc, and noVNC installed."
    elif [[ "$HAVE_SUDO" == false ]]; then
      warn "No sudo access. Skipping system packages. Run manually: sudo apt install xvfb x11vnc novnc"
    else
      warn "apt-get not available. Please install xvfb, x11vnc, and novnc manually."
    fi
  else
    warn "Skipping system packages (--skip-system)."
  fi

  # Python package: websockify
  if [[ -n "$PIP_CMD" ]]; then
    log "Installing websockify via pip..."
    "$PIP_CMD" install websockify --quiet 2>/dev/null || {
      warn "Failed to install websockify. VNC features may not work."
    }
    ok "websockify installed."
  else
    warn "pip not found, skipping websockify."
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "${BOLD}============================================================${RESET}"
if [[ "$ERRORS" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  All dependencies installed successfully!${RESET}"
else
  echo -e "${YELLOW}${BOLD}  Dependencies installed with $ERRORS error(s).${RESET}"
  echo -e "  Check the output above for details."
fi
echo -e "${BOLD}============================================================${RESET}"
echo ""
echo -e "  Next steps:"
echo -e "    1. Build the project:  ${CYAN}npm run build${RESET}"
echo -e "    2. Register services:  ${CYAN}sudo ./ops/install.sh${RESET}"
echo ""

exit "$ERRORS"
