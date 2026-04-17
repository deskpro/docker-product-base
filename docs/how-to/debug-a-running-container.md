---
title: Debug a running Deskpro container
type: how-to
last_reviewed: 2026-04-17
status: current
---

# Debug a running Deskpro container

Approaches, in rough order of invasiveness.

## Check logs first

If logs go to stdout:

```bash
docker logs --tail=200 -f <container>
```

If they're exported to a directory (because `/deskpro/logs/` is mounted), look there. A utility like [lnav](https://lnav.org/) makes logfmt pleasant to read:

```bash
lnav ./deskpro-logs/
```

The boot-phase log (from the entrypoint scripts, before supervisord starts) is always at `/var/log/docker-boot.log` inside the container. If something failed very early, check that file even if you can't see it in the normal stream.

To increase verbosity, restart with `BOOT_LOG_LEVEL=DEBUG` and `DESKPRO_LOG_LEVEL=debug`.

## Shell into a running container

```bash
docker exec -it <container> bash
```

This drops you in with the container's user context and `PATH`. All the helper CLIs (`container-var`, `healthcheck`, `mysql-read`, etc.) are available. See [helper-scripts.md](../reference/helper-scripts.md).

## Start a fresh, isolated container for debugging

```bash
docker run -it --rm --env-file config.env \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION bash
```

Services still start in the background (vector, container-ready, etc.). The env file gives you the same configuration as production. `--rm` cleans up on exit.

For a container that runs a single command and exits:

```bash
docker run --rm -it --env-file config.env \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION \
    exec php -r 'echo PHP_VERSION;'
```

## Read configuration values

Most env vars are stripped from the process environment at boot (moved into `/run/container-config/`). Use `container-var` instead of `printenv`:

```bash
container-var DESKPRO_DB_HOST
container-var DESKPRO_DB_PASS       # Works for private vars too
print-container-vars | sort         # Everything
```

## Database access

```bash
mysql-primary                       # Interactive read/write client
mysql-read                          # Read-only (uses replica if configured)
mysql-read -e 'SELECT COUNT(*) FROM tickets'
mysqldump-primary --hex-blob --single-transaction deskpro > /tmp/dump.sql
```

## Manually invoke background jobs

Sometimes a cron task is failing and you want to see its output directly:

```bash
# Generic cron loop
dpv5/bin/cron --verbose

# Email collection
services/email-processing/artisan email:collect-queue --max-time=60 --verbose

# Email processing
services/email-processing/artisan email:process-queue --max-time=60 --verbose
```

To freeze the cron loop without stopping the container (useful while diagnosing):

```bash
touch /deskpro/config/PAUSE_CRON
```

Delete the file to resume.

## Inspect a PHP-FPM pool

```bash
phpfpminfo                          # All pools
phpfpminfo --pool dp_default        # One pool's resolved config
phpinfo --fpm                       # phpinfo() as FPM sees it
curl -s http://127.0.0.1:10001/fpm/dp_default/status?json
```

## Healthcheck probes

```bash
healthcheck                         # What the Docker HEALTHCHECK runs
healthcheck --test-db --test-http --test-discover
is-ready                            # Just "has boot finished?"
```

## Agent login token (when locked out)

```bash
dpv5/bin/console dp:login-token admin@example.com
```

Gives you a URL to paste into a browser for a one-shot login.

## Disable the shutdown-on-failure guard

Supervisord normally kills the container when a service enters `FATAL`. To keep it alive so you can exec in and inspect:

```bash
docker run -e NO_SHUTDOWN_ON_ERROR=true ...
```

Don't leave this enabled in production — a failing container that keeps running is worse than one that restarts.

## Raw log files

If vector itself is broken, the per-service log files are still in `/var/log/` — `/var/log/nginx/`, `/var/log/php/`, `/var/log/deskpro/`, `/var/log/supervisor/`. These are the source streams vector is aggregating.
