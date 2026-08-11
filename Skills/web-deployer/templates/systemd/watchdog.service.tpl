[Unit]
Description={{PROJECT_NAME}} Health Check Watchdog
# {{IF HAS_BACKEND}}
After={{PROJECT_NAME}}-backend.service
# {{ENDIF HAS_BACKEND}}
# {{IF HAS_FRONTEND}}
After={{PROJECT_NAME}}-frontend.service
# {{ENDIF HAS_FRONTEND}}

[Service]
Type=oneshot
ExecStart={{PROJECT_DIR}}/ops/healthcheck.sh
User=root
