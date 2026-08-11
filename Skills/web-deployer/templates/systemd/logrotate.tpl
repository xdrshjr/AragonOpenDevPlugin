{{PROJECT_DIR}}/{{LOG_DIR}}/*.log {
    size {{LOG_MAX_SIZE}}
    rotate {{LOG_ROTATE_COUNT}}
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 0644 {{RUN_USER}} {{RUN_GROUP}}
}
