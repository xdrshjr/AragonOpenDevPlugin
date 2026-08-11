#!/usr/bin/env bash
# =============================================================================
# InkClaw — Service status query
# Displays the health of all InkClaw systemd services, ports, watchdog state,
# recent restart records, and log tails.
#
# Usage: ./ops/status.sh          (no sudo required)
# Exit codes: 0 = all OK, 1 = some abnormal, 2 = not installed
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# ---------------------------------------------------------------------------
# Defaults (overridden by config.env if present)
# ---------------------------------------------------------------------------
BACKEND_PORT=5000
FRONTEND_PORT=3000
WATCHDOG_FAIL_THRESHOLD=3
WATCHDOG_STATE_DIR=/tmp

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=config.env
  source "$CONFIG_FILE"
fi

# ---------------------------------------------------------------------------
# Colors (matching deployment.sh style)
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Disable colors when stdout is not a terminal.
if [[ ! -t 1 ]]; then
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Track overall health: 0 = all ok, 1 = degraded.
EXIT_CODE=0

print_header() {
  echo ""
  echo -e "${BOLD}============================================================${RESET}"
  echo -e "${BOLD}  InkClaw 服务状态${RESET}"
  echo -e "${BOLD}============================================================${RESET}"
}

print_footer() {
  echo -e "${BOLD}============================================================${RESET}"
  echo ""
}

section() {
  echo ""
  echo -e "  ${BOLD}$1${RESET}"
  echo -e "  ─────────────────────────"
}

# Print a key-value pair with consistent formatting.
kv() {
  local key="$1"
  shift
  printf "  %-12s %b\n" "$key" "$*"
}

# ---------------------------------------------------------------------------
# Pre-flight: check that systemd services are installed
# ---------------------------------------------------------------------------
BACKEND_UNIT="inkclaw-backend.service"
FRONTEND_UNIT="inkclaw-frontend.service"
WATCHDOG_TIMER="inkclaw-watchdog.timer"

check_installed() {
  local missing=0
  for unit in "$BACKEND_UNIT" "$FRONTEND_UNIT"; do
    if ! systemctl list-unit-files "$unit" --no-pager 2>/dev/null | grep -q "$unit"; then
      missing=1
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    echo ""
    echo -e "  ${YELLOW}InkClaw systemd 服务尚未安装。${RESET}"
    echo -e "  运行 ${BOLD}sudo ./ops/install.sh${RESET} 进行安装。"
    echo ""
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Service status helper
# ---------------------------------------------------------------------------
show_service_status() {
  local unit="$1"
  local label="$2"
  local port="$3"
  local health_url="$4"

  section "$label ($unit)"

  # Active state + PID
  local active_state
  active_state=$(systemctl show "$unit" --property=ActiveState --value 2>/dev/null) || active_state="unknown"

  local main_pid
  main_pid=$(systemctl show "$unit" --property=MainPID --value 2>/dev/null) || main_pid="0"

  local status_color="$GREEN"
  local status_icon="●"
  if [[ "$active_state" != "active" ]]; then
    status_color="$RED"
    EXIT_CODE=1
  fi

  if [[ "$main_pid" != "0" && -n "$main_pid" ]]; then
    kv "状态:" "${status_color}${status_icon} ${active_state}${RESET}  PID: ${CYAN}${main_pid}${RESET}"
  else
    kv "状态:" "${status_color}${status_icon} ${active_state}${RESET}"
  fi

  # Uptime
  local timestamp
  timestamp=$(systemctl show "$unit" --property=ActiveEnterTimestamp --value 2>/dev/null) || timestamp=""
  if [[ -n "$timestamp" && "$timestamp" != "n/a" && "$active_state" == "active" ]]; then
    local since_epoch
    since_epoch=$(date -d "$timestamp" +%s 2>/dev/null) || since_epoch=""
    if [[ -n "$since_epoch" ]]; then
      local now_epoch
      now_epoch=$(date +%s)
      local diff=$((now_epoch - since_epoch))
      local days=$((diff / 86400))
      local hours=$(( (diff % 86400) / 3600 ))
      local mins=$(( (diff % 3600) / 60 ))
      if [[ "$days" -gt 0 ]]; then
        kv "运行时间:" "${days}d ${hours}h ${mins}m"
      elif [[ "$hours" -gt 0 ]]; then
        kv "运行时间:" "${hours}h ${mins}m"
      else
        kv "运行时间:" "${mins}m"
      fi
    fi
  fi

  # Port check
  local port_status
  if ss -tlnH sport = :"$port" 2>/dev/null | grep -q .; then
    port_status="${GREEN}:${port} ✓ 监听中${RESET}"
  else
    port_status="${RED}:${port} ✗ 未监听${RESET}"
    EXIT_CODE=1
  fi
  kv "端口:" "$port_status"

  # HTTP health check
  local http_code
  http_code=$(curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "$health_url" 2>/dev/null) || http_code="000"
  if [[ "$http_code" =~ ^2 ]]; then
    kv "健康检查:" "${GREEN}${health_url} → ${http_code} OK${RESET}"
  else
    kv "健康检查:" "${RED}${health_url} → ${http_code} FAIL${RESET}"
    EXIT_CODE=1
  fi
}

# ---------------------------------------------------------------------------
# Watchdog status
# ---------------------------------------------------------------------------
show_watchdog_status() {
  section "看门狗 ($WATCHDOG_TIMER)"

  # Timer active state
  local timer_state
  timer_state=$(systemctl show "$WATCHDOG_TIMER" --property=ActiveState --value 2>/dev/null) || timer_state="unknown"

  local timer_sub
  timer_sub=$(systemctl show "$WATCHDOG_TIMER" --property=SubState --value 2>/dev/null) || timer_sub=""

  local timer_color="$GREEN"
  if [[ "$timer_state" != "active" ]]; then
    timer_color="$YELLOW"
  fi

  kv "状态:" "${timer_color}● ${timer_state}${RESET}${timer_sub:+ (${timer_sub})}"

  # Next trigger time
  local next_trigger
  next_trigger=$(systemctl show "$WATCHDOG_TIMER" --property=NextElapseUSecRealtime --value 2>/dev/null) || next_trigger=""
  if [[ -n "$next_trigger" && "$next_trigger" != "n/a" ]]; then
    # Convert from systemd timestamp format
    local next_readable
    next_readable=$(date -d "$next_trigger" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || next_readable="$next_trigger"
    kv "下次检查:" "$next_readable"
  fi

  # Failure counters
  local backend_failures=0
  local frontend_failures=0
  local counter_file

  counter_file="${WATCHDOG_STATE_DIR}/inkclaw-watchdog-backend-failures"
  if [[ -f "$counter_file" ]]; then
    backend_failures=$(<"$counter_file") || true
    [[ "$backend_failures" =~ ^[0-9]+$ ]] || backend_failures=0
  fi

  counter_file="${WATCHDOG_STATE_DIR}/inkclaw-watchdog-frontend-failures"
  if [[ -f "$counter_file" ]]; then
    frontend_failures=$(<"$counter_file") || true
    [[ "$frontend_failures" =~ ^[0-9]+$ ]] || frontend_failures=0
  fi

  local threshold="${WATCHDOG_FAIL_THRESHOLD}"

  local be_color="$GREEN"
  if [[ "$backend_failures" -gt 0 ]]; then
    be_color="$YELLOW"
  fi
  if [[ "$backend_failures" -ge "$threshold" ]]; then
    be_color="$RED"
  fi
  kv "后端失败计数:" "${be_color}${backend_failures}/${threshold}${RESET}"

  local fe_color="$GREEN"
  if [[ "$frontend_failures" -gt 0 ]]; then
    fe_color="$YELLOW"
  fi
  if [[ "$frontend_failures" -ge "$threshold" ]]; then
    fe_color="$RED"
  fi
  kv "前端失败计数:" "${fe_color}${frontend_failures}/${threshold}${RESET}"
}

# ---------------------------------------------------------------------------
# Nginx reverse proxy status
# ---------------------------------------------------------------------------
show_nginx_status() {
  section "Nginx 反向代理"

  if ! command -v nginx >/dev/null 2>&1; then
    kv "状态:" "${YELLOW}未安装${RESET}"
    return
  fi

  local nginx_state
  nginx_state=$(systemctl is-active nginx 2>/dev/null) || nginx_state="unknown"
  local nginx_color="$GREEN"
  if [[ "$nginx_state" != "active" ]]; then
    nginx_color="$RED"
    EXIT_CODE=1
  fi
  kv "状态:" "${nginx_color}● ${nginx_state}${RESET}"

  local site_name="${NGINX_SITE_NAME:-inkclaw}"
  local nginx_conf="/etc/nginx/sites-available/$site_name"
  if [[ -f "$nginx_conf" ]]; then
    local domain
    domain=$(grep -oP 'server_name\s+\K[^;]+' "$nginx_conf" 2>/dev/null | head -1 | xargs) || domain=""
    if [[ -n "$domain" ]]; then
      kv "域名:" "${CYAN}${domain}${RESET}"
    fi

    # Check SSE settings
    if grep -q "proxy_buffering off" "$nginx_conf" && grep -q "proxy_read_timeout 3600s" "$nginx_conf"; then
      kv "SSE设置:" "${GREEN}✓ 已配置${RESET}"
    else
      kv "SSE设置:" "${RED}✗ 缺少 proxy_buffering/timeout 设置${RESET}"
      EXIT_CODE=1
    fi
  else
    kv "配置:" "${YELLOW}未找到 ${nginx_conf}${RESET}"
  fi
}

# ---------------------------------------------------------------------------
# Recent restart records
# ---------------------------------------------------------------------------
show_restart_records() {
  section "最近重启记录"

  local records
  records=$(journalctl -u "$BACKEND_UNIT" -u "$FRONTEND_UNIT" \
    --since "7 days ago" --grep "Started\|Stopped\|restart" \
    --no-pager -n 20 --no-hostname 2>/dev/null) || records=""

  if [[ -z "$records" ]]; then
    echo -e "  ${CYAN}(无最近重启记录)${RESET}"
  else
    echo "$records" | while IFS= read -r line; do
      echo "  $line"
    done
  fi
}

# ---------------------------------------------------------------------------
# Recent logs
# ---------------------------------------------------------------------------
show_recent_logs() {
  section "最近日志 (最后 10 行)"

  echo -e "  ${BOLD}[后端]${RESET}"
  local backend_logs
  backend_logs=$(journalctl -u "$BACKEND_UNIT" --no-pager -n 5 --no-hostname 2>/dev/null) || backend_logs=""
  if [[ -z "$backend_logs" ]]; then
    echo -e "  ${CYAN}(无日志)${RESET}"
  else
    echo "$backend_logs" | while IFS= read -r line; do
      echo "  $line"
    done
  fi

  echo ""
  echo -e "  ${BOLD}[前端]${RESET}"
  local frontend_logs
  frontend_logs=$(journalctl -u "$FRONTEND_UNIT" --no-pager -n 5 --no-hostname 2>/dev/null) || frontend_logs=""
  if [[ -z "$frontend_logs" ]]; then
    echo -e "  ${CYAN}(无日志)${RESET}"
  else
    echo "$frontend_logs" | while IFS= read -r line; do
      echo "  $line"
    done
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  check_installed

  print_header

  show_service_status "$BACKEND_UNIT" "后端服务" "$BACKEND_PORT" \
    "http://localhost:${BACKEND_PORT}/health"

  show_service_status "$FRONTEND_UNIT" "前端服务" "$FRONTEND_PORT" \
    "http://localhost:${FRONTEND_PORT}/"

  show_watchdog_status
  show_nginx_status
  show_restart_records
  show_recent_logs

  echo ""
  print_footer

  exit "$EXIT_CODE"
}

main
