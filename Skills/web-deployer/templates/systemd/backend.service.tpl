[Unit]
Description={{PROJECT_NAME}} Backend ({{BACKEND_FRAMEWORK}})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{RUN_USER}}
Group={{RUN_GROUP}}
WorkingDirectory={{PROJECT_DIR}}/{{BACKEND_SUBDIRECTORY}}
Environment=NODE_ENV=production
Environment=PORT={{BACKEND_PORT}}
Environment=PATH={{PATH_DIRS}}
ExecStart={{BACKEND_START}}
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
SyslogIdentifier={{PROJECT_NAME}}-backend

[Install]
WantedBy=multi-user.target
