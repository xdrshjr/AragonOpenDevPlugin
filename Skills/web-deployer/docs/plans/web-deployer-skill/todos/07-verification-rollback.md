# TODO 07: Verification & Rollback

**Spec Reference:** [specs/07-verification-rollback.md](../specs/07-verification-rollback.md)

## Dependencies

- `depends_on: [04, 05, 06]` — needs services deployed and Nginx configured
- `blocks: [09]` — workflow needs verification results to proceed to summary
- `parallel_group: D`

## Tasks

- [x] Write quick verification checks: HTTP health, service active state, port listening
- [x] Write full verification checks: Nginx config, SSL cert, watchdog, logs, disk, memory
- [x] Write Docker-specific verification: container running, container healthy
- [x] Write verification report formatting (pass/fail per check with details)
- [x] Write pre-deployment backup logic: systemd units, Nginx config, config.env
- [x] Write Docker pre-deployment backup: container state, compose file, image tagging
- [x] Write failure report generation with diagnostic info
- [x] Write user decision prompt on failure: retry, rollback, manual, skip
- [x] Write systemd rollback execution: restore units, reload, restart
- [x] Write Docker rollback execution: restore compose, retag images, restart
- [x] Write backup retention cleanup (keep last 5)
- [x] Write multi-server verification summary
