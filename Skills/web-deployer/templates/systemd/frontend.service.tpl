[Unit]
Description={{PROJECT_NAME}} Frontend ({{FRONTEND_FRAMEWORK}})
# {{IF HAS_BACKEND}}
After=network-online.target {{PROJECT_NAME}}-backend.service
Wants=network-online.target
Requires={{PROJECT_NAME}}-backend.service
# {{ENDIF HAS_BACKEND}}
# {{IF_NOT HAS_BACKEND}}
After=network-online.target
Wants=network-online.target
# {{ENDIF_NOT HAS_BACKEND}}

[Service]
Type=simple
User={{RUN_USER}}
Group={{RUN_GROUP}}
WorkingDirectory={{PROJECT_DIR}}/{{FRONTEND_SUBDIRECTORY}}
Environment=NODE_ENV=production
Environment=PORT={{FRONTEND_PORT}}
Environment=PATH={{PATH_DIRS}}
ExecStart={{FRONTEND_START}}
Restart=on-failure
RestartSec=5s
StartLimitBurst=5
StartLimitIntervalSec=300

# Security hardening
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths={{PROJECT_DIR}} {{USER_DATA_DIR}}
PrivateTmp=false

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier={{PROJECT_NAME}}-frontend

[Install]
WantedBy=multi-user.target
