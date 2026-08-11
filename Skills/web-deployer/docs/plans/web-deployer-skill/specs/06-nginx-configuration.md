# Spec 06: Nginx Configuration

## Purpose

Auto-configure Nginx as a reverse proxy for deployed services, with SSL detection, SSE/WebSocket support, and template-based configuration.

## When Nginx is Configured

Nginx configuration is triggered when:
1. User provides `NGINX_DOMAIN` (domain name)
2. Nginx is installed on the server (detected in pre-flight)
3. User does not explicitly skip Nginx (`--no-nginx`)

## SSL Detection Strategy

```
1. Check Let's Encrypt: /etc/letsencrypt/live/{primary_domain}/fullchain.pem
2. Check existing Nginx config for ssl_certificate paths
3. Check common locations: /etc/ssl/certs/, /etc/nginx/ssl/
4. If no SSL found → use HTTP-only template, warn user
```

## Template: HTTPS (site-https.tpl)

```nginx
# {{PROJECT_NAME}} nginx config v1
server {
    listen 443 ssl http2;
    server_name {{NGINX_DOMAIN}};

    ssl_certificate     {{NGINX_SSL_CERT}};
    ssl_certificate_key {{NGINX_SSL_KEY}};
{{NGINX_SSL_EXTRA}}
    client_max_body_size 50m;

    location / {
        proxy_pass http://localhost:{{FRONTEND_PORT}};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        # SSE/streaming support
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 60s;
        chunked_transfer_encoding on;
    }

    {{IF BACKEND_DETECTED}}
    # API proxy (direct backend access)
    location /api/ {
        proxy_pass http://localhost:{{BACKEND_PORT}}/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        chunked_transfer_encoding on;
    }
    {{ENDIF BACKEND_DETECTED}}
}

server {
    listen 80;
    server_name {{NGINX_DOMAIN}};

    if ($http_x_forwarded_proto != "https") {
        return 301 https://$host$request_uri;
    }

    location / {
        proxy_pass http://localhost:{{FRONTEND_PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_buffering off;
        proxy_read_timeout 3600s;
    }
}
```

## Template: HTTP-Only (site-http.tpl)

Same as HTTPS but without SSL directives, single `listen 80` server block.

## Installation Process

1. Render the appropriate template (HTTPS or HTTP)
2. Write to `/etc/nginx/sites-available/{{NGINX_SITE_NAME}}`
3. Create symlink in `/etc/nginx/sites-enabled/`
4. Backup existing config if present (timestamped `.bak`)
5. Clean duplicate domain blocks from default site
6. Remove stale `.bak` files from `sites-enabled/`
7. Test config: `nginx -t`
8. Reload: `systemctl reload nginx`
9. On failure: restore backup, reload, report error

## Version Detection

Each generated Nginx config includes a version marker comment:
```
# {{PROJECT_NAME}} nginx config v1
```

If this marker exists in the current config, skip reconfiguration (idempotent).
Override with `--force-nginx` flag.

## SSE/WebSocket Considerations

The SSE/streaming settings are critical for:
- Server-Sent Events (AI agent streaming, live updates)
- WebSocket connections (real-time features)
- Long-polling endpoints

Key settings:
- `proxy_buffering off` — prevents Nginx from buffering streamed responses
- `proxy_read_timeout 3600s` — allows 1-hour long connections
- `chunked_transfer_encoding on` — enables chunked responses
- `proxy_set_header Connection "upgrade"` — enables WebSocket upgrade

## Docker Mode Integration

When Docker deployment mode is used:
- Nginx still runs on the host (not in a container)
- Proxy targets are `localhost:PORT` (Docker publishes ports to host)
- Same templates apply; no Docker-specific Nginx changes needed

## Multi-Domain Support

`NGINX_DOMAIN` supports space-separated domains:
```
NGINX_DOMAIN="example.com www.example.com"
```

The `server_name` directive handles multiple domains natively.
