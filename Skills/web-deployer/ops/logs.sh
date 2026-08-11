#!/usr/bin/env bash
# =============================================================================
# InkClaw — Service log viewer
# Displays recent logs from InkClaw systemd services via journalctl.
#
# Usage:
#   ./ops/logs.sh                    # last 50 lines from all services
#   ./ops/logs.sh frontend           # last 50 lines from frontend
#   ./ops/logs.sh backend -n 100     # last 100 lines from backend
#   ./ops/logs.sh frontend -f        # follow frontend logs
#   ./ops/logs.sh all -n 20          # last 20 lines from each service
#   ./ops/logs.sh watchdog           # last 50 lines from watchdog
#
# No sudo required.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (matches deployment.sh / status.sh style)
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Service names
# ---------------------------------------------------------------------------
FRONTEND_SERVICE="inkclaw-frontend.service"
BACKEND_SERVICE="inkclaw-backend.service"
WATCHDOG_SERVICE="inkclaw-watchdog.service"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
TARGET="all"
LINE_COUNT=50
FOLLOW=false

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo -e "${BOLD}InkClaw Log Viewer${RESET}"
    echo ""
    echo "Usage: $0 [frontend|backend|watchdog|all] [-n <count>] [-f]"
    echo ""
    echo "Arguments:"
    echo "  frontend    Show logs from ${FRONTEND_SERVICE}"
    echo "  backend     Show logs from ${BACKEND_SERVICE}"
    echo "  watchdog    Show logs from ${WATCHDOG_SERVICE}"
    echo "  all         Show logs from all services (default)"
    echo ""
    echo "Options:"
    echo "  -n <count>  Number of log lines to show (default: 50)"
    echo "  -f          Follow logs in real-time"
    echo "  -h          Show this help message"
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
# First, check if positional argument is provided
if [[ $# -gt 0 ]]; then
    case "$1" in
        frontend|backend|watchdog|all)
            TARGET="$1"
            shift
            ;;
        -n|-f|-h|--help)
            # Not a target, leave it for getopts
            ;;
        *)
            echo -e "${RED}Error: Unknown target '$1'. Use frontend, backend, watchdog, or all.${RESET}"
            echo ""
            usage
            ;;
    esac
fi

# Parse optional flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: -n requires a numeric argument.${RESET}"
                exit 1
            fi
            LINE_COUNT="$2"
            shift 2
            ;;
        -f)
            FOLLOW=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'.${RESET}"
            echo ""
            usage
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
print_header() {
    local service_name="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN}  ▶ ${service_name}${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

check_service_exists() {
    local service="$1"
    if ! systemctl list-unit-files "$service" &>/dev/null; then
        return 1
    fi
    # Check if the unit file is actually known to systemd
    if systemctl list-unit-files "$service" 2>/dev/null | grep -q "$service"; then
        return 0
    fi
    return 1
}

show_logs() {
    local service="$1"
    local display_name="$2"

    print_header "$display_name"

    if ! check_service_exists "$service"; then
        echo -e "  ${YELLOW}Service ${service} is not installed. Skipping.${RESET}"
        echo ""
        return
    fi

    if [[ "$FOLLOW" == true ]]; then
        echo -e "  ${YELLOW}Following logs (Ctrl+C to stop)...${RESET}"
        echo ""
        journalctl -u "$service" -f --no-pager
    else
        journalctl -u "$service" -n "$LINE_COUNT" --no-pager
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}InkClaw Log Viewer${RESET}"
echo -e "Target: ${GREEN}${TARGET}${RESET}  |  Lines: ${GREEN}${LINE_COUNT}${RESET}  |  Follow: ${GREEN}${FOLLOW}${RESET}"

case "$TARGET" in
    frontend)
        show_logs "$FRONTEND_SERVICE" "Frontend (Next.js)"
        ;;
    backend)
        show_logs "$BACKEND_SERVICE" "Backend (Flask)"
        ;;
    watchdog)
        show_logs "$WATCHDOG_SERVICE" "Watchdog (Health Check)"
        ;;
    all)
        show_logs "$BACKEND_SERVICE" "Backend (Flask)"
        show_logs "$FRONTEND_SERVICE" "Frontend (Next.js)"
        # Watchdog is optional — only show if installed
        if check_service_exists "$WATCHDOG_SERVICE"; then
            show_logs "$WATCHDOG_SERVICE" "Watchdog (Health Check)"
        fi
        ;;
esac

if [[ "$FOLLOW" != true ]]; then
    echo ""
    echo -e "${CYAN}Tip: Use ${BOLD}-f${RESET}${CYAN} to follow logs in real-time, or ${BOLD}-n <count>${RESET}${CYAN} to adjust line count.${RESET}"
fi
