---
title: Ports and mount conventions
type: reference
last_reviewed: 2026-04-17
status: current
---

# Ports and mount conventions

## Exposed ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| `80` | HTTP | Public web traffic. |
| `443` | HTTPS | Public web traffic, when an SSL cert is mounted or the testing cert is enabled. |
| `9080` | HTTP + [PROXY protocol](https://www.haproxy.com/blog/use-the-proxy-protocol-to-preserve-a-clients-ip-address) | Behind a PROXY-protocol-aware load balancer. Client IP and port are read directly from the PROXY header. |
| `9443` | HTTPS + PROXY protocol | As above, TLS-terminated. |
| `10001` | HTTP (status) | Internal endpoints: `/nginx/status`, `/fpm/<pool>/status`, Prometheus metrics if enabled. Do NOT expose publicly. |

`9080` / `9443` are recommended when the container sits behind a load balancer that speaks PROXY protocol, because the real client IP and port are carried by the protocol instead of being trusted from arbitrary HTTP headers.

## Mount conventions (`/deskpro/`)

The "custom mount basedir" (`CUSTOM_MOUNT_BASEDIR`, default `/deskpro`) is the operator extension point. The entrypoint looks for specific subdirectories:

### `/deskpro/config/`

| Subpath | Purpose | Notes |
| --- | --- | --- |
| `deskpro-config.d/*.php` | Deskpro app PHP config snippets. Extend `$CONFIG`, don't overwrite it. | `.tmpl` variants rendered via gomplate. |
| `nginx.d/*.conf` | Extra nginx config. | Included alongside built-in `/etc/nginx/conf.d/`. |
| `php-fpm.d/*.conf` | Extra PHP-FPM pool / global config. Needs `[pool_name]` header if setting pool values. | |
| `php.d/*.ini` | Extra `php.ini` fragments. | Applied to both CLI and FPM. |
| `vector.d/*.toml` | Custom vector sources / transforms / sinks. | Use the `all` or `all_formatted` inputs. |
| `config.custom.php` | Legacy single-file custom config. | Symlinked into place. |
| `PAUSE_CRON` | Sentinel. If this file exists, `tasksd` will not invoke `bin/cron`. | Touch it to freeze background task execution. |

Files are **copied** into the image at boot (not bind-mounted in place), so permissions on the mount don't need to match the in-container user — the entrypoint fixes them. Mount them as `root:root` with mode `0600` or `0400` for secrets.

Changes require a container restart. Editing files after boot has no effect.

Include order is lexicographic, so prefix with `99-` if you want your file applied last.

### `/deskpro/ssl/`

| Subpath | Purpose |
| --- | --- |
| `certs/deskpro-https.crt` | HTTPS certificate (PEM). Enables port 443. |
| `private/deskpro-https.key` | HTTPS private key (unencrypted). |
| `ca-certificates/*.crt` | Extra CA certificates, copied into the system trust store. |
| `mysql/client.crt` + `mysql/client.key` | Enables TLS for MySQL connections. |
| `mysql/ca.pem` | Custom CA for MySQL server verification. |

### `/deskpro/logs/`

If this directory exists, the entrypoint defaults `LOGS_EXPORT_TARGET=dir` and `LOGS_EXPORT_DIR=/deskpro/logs`. Vector will write normalised logs here instead of stdout. Set `LOGS_GID` to control file group ownership. Host-side log rotation is YOUR responsibility.

### `/deskpro/entrypoint.d/`

Any `*.sh` files here run at boot after the built-in entrypoint scripts. Use this to add custom bootstrapping (e.g. fetch secrets from an internal service).

## Persistent data

Mount `/srv/deskpro/INSTANCE_DATA/` as a persistent volume whenever `DESKPRO_STORAGE_TYPE=fs` (it holds attachments) or whenever you want generated runtime config (`deskpro-config.d/`) to survive restarts. S3 and DB storage don't require a volume here.

## Sentinel files (read-only for operators)

Under `/run/` the entrypoint creates several files you can probe for state:

| File | Meaning |
| --- | --- |
| `/run/container-booted` | Timestamp when supervisord started. |
| `/run/container-ready` | Installer and migrations finished. `is-ready` returns 0. |
| `/run/container-running-installer` | Installer is executing. |
| `/run/container-running-migrations` | Migrations are executing. |
| `/run/deskpro-cron-status.json` | Last cron iteration timings. |
| `/run/container-config/<VAR>` | Materialised env-var values. Mode `1711`. |
