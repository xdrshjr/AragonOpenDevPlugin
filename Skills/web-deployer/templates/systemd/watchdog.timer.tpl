[Unit]
Description={{PROJECT_NAME}} Watchdog Timer

[Timer]
OnBootSec=120
OnUnitActiveSec={{WATCHDOG_INTERVAL}}s
AccuracySec=5s

[Install]
WantedBy=timers.target
