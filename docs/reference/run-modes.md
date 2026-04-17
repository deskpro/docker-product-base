---
title: Run modes
type: reference
last_reviewed: 2026-04-17
status: current
---

# Run modes

The container's `CMD` argument (or the first positional arg to `docker run <image>`) selects the run mode. It's parsed by [`usr/local/sbin/entrypoint.d/15-run-mode.sh`](../../usr/local/sbin/entrypoint.d/15-run-mode.sh), which sets the appropriate `SVC_*_ENABLED` env vars to tell supervisord which services to start.

The default, if no command is given, is `web`.

All other modes are essentially aliases for `svc <names...>`. At the recommended minimum, run two containers: one `web`, one `tasks`.

## Modes

| Mode | Services enabled | Typical use |
| --- | --- | --- |
| `web` | `nginx`, `php-fpm` | Public-facing web traffic. The default. Same as `svc web`. |
| `tasks` | `tasks` (cron loop) | Background task scheduler. Runs `bin/cron` every 20s. Same as `svc tasks`. |
| `email_collect` | `email_collect` | IMAP polling workers. Fetches mail into Deskpro. |
| `email_process` | `email_process` | Email queue workers. Processes fetched messages. |
| `combined` | `nginx`, `php-fpm`, `tasks` | Quick start / small installs. Same as `svc web tasks`. Not recommended at scale because tasks and web compete for resources. |
| `svc <names...>` | Only the named services | Flexible composition. Names: `web` / `http` / `nginx` / `php_fpm`, `tasks`, `email_collect`, `email_process`. |
| `none` | None | Only supervisord housekeeping (vector, container-ready, rotate_logs). Useful for debugging boot. |
| `bash` | All of the above, plus an interactive shell | Supervisord runs in the background and an interactive `bash` takes over stdio. |
| `exec <cmd> [args...]` | All of the above, plus the given command | Same as `bash`, but executes `<cmd>` instead of a shell. |

## How each mode starts

```bash
# Defaults to web
docker run deskpro/docker-product-base:latest

# Explicit web
docker run deskpro/docker-product-base:latest web

# Background task scheduler
docker run deskpro/docker-product-base:latest tasks

# Email collection, with overridden concurrency
docker run -e SVC_EMAIL_COLLECT_NUMPROCS=4 \
    deskpro/docker-product-base:latest email_collect

# Two services in the same container
docker run deskpro/docker-product-base:latest svc nginx php_fpm tasks

# Shell for debugging, with services running in the background
docker run -it deskpro/docker-product-base:latest bash

# One-off artisan command, services running in the background so the command
# can call the localhost API
docker run --rm deskpro/docker-product-base:latest \
    exec php /srv/deskpro/bin/artisan <command>
```

## Auto-starting the web service for task modes

Modes like `tasks`, `email_collect`, and `exec <something>` may call back into the Deskpro API at `DESKPRO_API_BASE_URL_PRIVATE` (default `http://127.0.0.1:80`). If that URL points to localhost, `15-run-mode.sh` transparently enables `SVC_NGINX_ENABLED` and `SVC_PHP_FPM_ENABLED` so the internal API is reachable. To suppress this — e.g., because you route the API to a different container — set `DESKPRO_API_BASE_URL_PRIVATE` to a non-local URL.

## The `SVC_*_ENABLED` contract

The run-mode script sets these variables:

| Variable | Services |
| --- | --- |
| `SVC_NGINX_ENABLED` | nginx |
| `SVC_PHP_FPM_ENABLED` | PHP-FPM pools |
| `SVC_TASKS_ENABLED` | `tasksd` cron loop |
| `SVC_EMAIL_COLLECT_ENABLED` | IMAP workers |
| `SVC_EMAIL_PROCESS_ENABLED` | Email queue workers |

These are all read in the supervisord config templates (`etc/supervisor/conf.d/*.conf.tmpl`) to set `autostart`. They are `isPrivate: true` in the var reference — you can override them, but doing so bypasses the run-mode logic and generally isn't necessary.

## Picking a deployment topology

- **Single-container, single-tenant, small traffic**: `combined` is fine.
- **Kubernetes / Docker Compose with multiple replicas**: split into `web` deployments (horizontally scalable) and a single `tasks` replica. Add `email_collect` and `email_process` as separate deployments when mail volume warrants it.
- **Debugging a running installation**: `docker exec` into a running `web` container, or start a sidecar with `bash` mode.

The related how-to is [run-background-tasks-separately.md](../how-to/run-background-tasks-separately.md).
