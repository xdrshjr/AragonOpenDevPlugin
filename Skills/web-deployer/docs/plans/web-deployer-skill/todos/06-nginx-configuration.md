# TODO 06: Nginx Configuration

**Spec Reference:** [specs/06-nginx-configuration.md](../specs/06-nginx-configuration.md)

## Dependencies

- `depends_on: [02, 03]` — needs rendered templates and SSH connection
- `blocks: [07]` — verification checks Nginx config
- `parallel_group: C`

## Tasks

- [x] Write SSL detection logic: Let's Encrypt, existing config, common locations
- [x] Write template selection: HTTPS vs HTTP-only based on SSL detection
- [x] Write Nginx config installation sequence: render, write, symlink, backup
- [x] Write duplicate domain cleanup from default site
- [x] Write Nginx config test and reload with failure recovery
- [x] Write version marker detection for idempotent configuration
- [x] Write API proxy location block (conditional, for fullstack projects with separate backend)
- [x] Write multi-domain support in server_name directive
