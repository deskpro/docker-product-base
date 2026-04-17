---
title: Environment variable reference
type: reference
last_reviewed: 2026-04-17
status: current
---

# Environment variable reference

The canonical, machine-readable list of every environment variable the image understands is [`usr/local/share/deskpro/container-var-reference.json`](../../usr/local/share/deskpro/container-var-reference.json). The product image, its tooling, and the entrypoint scripts all read from that file — when you add a variable, add it there first.

This document is a curated human index of that JSON, grouped by purpose. For the exhaustive list with full descriptions, read the JSON directly (it's the source of truth; this file can drift).

## Variable conventions

Three input suffixes are supported for any variable `VAR`:

| Suffix | Meaning | Example |
| --- | --- | --- |
| `VAR_B64` | Value is base64-encoded; decoded at boot. | `DESKPRO_DB_PASS_B64='bXkgJ3Bhc3N3b3JkJw=='` |
| `VAR_ESC` | Value contains escape sequences (`\n`, `\t`, …); unescaped at boot. | `PHP_FPM_OVERRIDES_ESC='a=1\nb=2'` |
| `VAR_FILE` | Value is read from the given file. | `DESKPRO_DB_PASS_FILE=/run/secrets/db_pass` |

Docker Swarm / Kubernetes secrets mounted at `/run/secrets/<name>` are auto-detected — the entrypoint sets `<NAME>_FILE` for each one without you having to declare it.

The `isPrivate: true` flag on a variable means its value is moved out of the process environment into `/run/container-config/<VAR>` at boot. To read a private variable inside the container, use `container-var <VAR>` or read the file via the `<VAR>_FILE` pointer.

## Required variables

| Variable | Purpose |
| --- | --- |
| `DESKPRO_APP_KEY` | 32 random bits, base64-encoded. Signing key. Must not change once set. |
| `DESKPRO_DB_HOST` | Primary database host. |
| `DESKPRO_DB_PORT` | Primary database port. Default `3306`. |
| `DESKPRO_DB_NAME` | Database name. Default `deskpro`. |
| `DESKPRO_DB_USER` / `DESKPRO_DB_PASS` | Credentials for the primary DB. |
| `DESKPRO_ES_URL` | Full Elasticsearch / OpenSearch URL (may include credentials). No trailing slash. |
| `DESKPRO_ES_INDEX_NAME` | Elastic index name. Default `deskpro`. |

Generate an app key with:

```bash
docker run --rm php:latest php -r 'echo "DESKPRO_APP_KEY=".var_export(base64_encode(random_bytes(32)),true).PHP_EOL;'
```

## Database — optional

| Variable | Purpose |
| --- | --- |
| `DESKPRO_DB_READ_HOST` / `_PORT` / `_USER` / `_PASS` / `_NAME` | Read replica. Any unset field falls back to the primary value. |
| `DESKPRO_DB_REPORTS_HOST` / `_PORT` / `_USER` / `_PASS` / `_NAME` | Reports / analytics DB. |

## Storage

| Variable | Purpose |
| --- | --- |
| `DESKPRO_STORAGE_TYPE` | `db` (default), `fs`, or `s3`. |
| `DESKPRO_STORAGE_SETTINGS` | JSON string. Shape depends on `DESKPRO_STORAGE_TYPE`. For S3: `bucket_name`, `bucket_region`, `access_key`, `secret_key`. |
| `DESKPRO_BLOBS_PATH` | Filesystem path for `fs` storage. Default `/srv/deskpro/INSTANCE_DATA/attachments`. Mount a persistent volume here. |

## Install & migrations

| Variable | Purpose |
| --- | --- |
| `AUTO_RUN_INSTALLER` | If `true` and the DB is empty, run installer on first boot. |
| `AUTO_RUN_MIGRATIONS` | If `true`, run pending migrations on boot. |
| `INSTALL_ADMIN_EMAIL` / `INSTALL_ADMIN_PASSWORD` / `INSTALL_URL` | Installer options. |

## HTTP / reverse proxy

| Variable | Purpose |
| --- | --- |
| `HTTP_SERVE_HOST` | Static host header (alternative to reading a proxy header). |
| `HTTP_USER_REAL_IP_HEADER` | Proxy header containing the real client IP. E.g. `X-Forwarded-For`, `True-Client-IP`, `CF-Connecting-IP`. |
| `HTTP_USER_REAL_HOST_HEADER` | Proxy header containing the real host. E.g. `X-Forwarded-Host`. |
| `HTTP_USER_REAL_PROTO_HEADER` | `X-Forwarded-Proto` or equivalent. |
| `HTTP_USER_REAL_PORT_HEADER` | `X-Forwarded-Port` or equivalent. |
| `HTTP_USER_SET_HTTP_PROTO` / `_PORT` | Static http proto / port (alternative to a header). |
| `HTTP_USER_SET_HTTPS_PROTO` / `_PORT` | Static https proto / port. |
| `HTTP_USE_TESTING_CERTIFICATE` | If `true`, listens on 443 with the bundled self-signed cert. Not safe for production — the cert is in the public image. |

See [how-to/configure-reverse-proxy.md](../how-to/configure-reverse-proxy.md) and [how-to/enable-https.md](../how-to/enable-https.md).

## Nginx

| Variable | Default |
| --- | --- |
| `NGINX_WORKER_PROCESSES` | `auto` |
| `NGINX_WORKER_CONNECTIONS` | `1000` |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `100M` |
| `NGINX_LARGE_CLIENT_HEADER_BUFFERS` | `4 16k` |
| `NGINX_ERROR_LOG_LEVEL` | `warn` |
| `SVC_NGINX_LISTEN_ADDRESS` | `*` |

## PHP

| Variable | Default |
| --- | --- |
| `PHP_MEMORY_LIMIT` | `1G` |
| `PHP_INI_OVERRIDES` | (multi-line string appended to php.ini) |
| `PHP_OPCACHE_ENABLED` | `1` |
| `PHP_OPCACHE_MEMORY_CONSUMPTION` | `128` (MB) |
| `PHP_OPCACHE_JIT_BUFFER_SIZE` | `0` |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `On` |

## PHP-FPM

Pool names: `DP_DEFAULT` (general), `DP_BROADCASTER` (long-lived broadcaster), `DP_GQL` (agent GraphQL), `DP_INTERNAL` (internal API).

| Variable | Default | Scope |
| --- | --- | --- |
| `PHP_FPM_PM_TYPE` | `ondemand` | Global default |
| `PHP_FPM_LISTEN_BACKLOG` | `1000` | Global |
| `PHP_FPM_LOG_LEVEL` | `notice` | Global |
| `PHP_FPM_OVERRIDES` | — | Appended to the `[global]` section |
| `PHP_FPM_POOL_OVERRIDES` | — | Appended to every pool |
| `PHP_FPM_<POOL>_PM_TYPE` | `ondemand` | Per pool |
| `PHP_FPM_<POOL>_MAX_CHILDREN` | `20` | Per pool |
| `PHP_FPM_<POOL>_OVERRIDES` | — | Per pool |

## Email services

| Variable | Default | Purpose |
| --- | --- | --- |
| `TASKS_DISABLE_EMAIL_IN_JOB` | `false` | Set `true` on the generic `tasks` container when running dedicated email containers. |
| `SVC_EMAIL_COLLECT_NUMPROCS` | `1` | Number of IMAP poller processes. |
| `SVC_EMAIL_COLLECT_ARGS_MAX_TIME` | `600` | Max seconds per process iteration. |
| `SVC_EMAIL_COLLECT_ARGS_EACH_MAX_TIME` | `30` | Max seconds per account. |
| `SVC_EMAIL_COLLECT_ARGS_TIMEOUT` | `45` | Hard timeout (prevents zombies). |
| `SVC_EMAIL_COLLECT_ARGS_ACCOUNT_REST` | `15` | Seconds between empty-account polls. |
| `SVC_EMAIL_COLLECT_ARGS_EXTRA` | — | Extra CLI args to the collect command. |
| `SVC_EMAIL_PROCESS_NUMPROCS` | `1` | Number of processor workers. |
| `SVC_EMAIL_PROCESS_ARGS_MAX_TIME` | `600` | Max seconds per iteration. |
| `SVC_EMAIL_PROCESS_ARGS_MAX_JOBS` | `300` | Jobs per iteration. |
| `SVC_EMAIL_PROCESS_ARGS_TIMEOUT` | `300` | Max seconds per single email. |
| `SVC_EMAIL_PROCESS_ARGS_TRIES` | `3` | Attempts before failing a message. |
| `SVC_EMAIL_PROCESS_ARGS_RESERVE_TIME` | `5` | Queue reservation time. |

## Logging

| Variable | Default | Purpose |
| --- | --- | --- |
| `LOGS_EXPORT_TARGET` | auto (`dir` if `LOGS_EXPORT_DIR` set, else `stdout`) | Where vector sends logs. Also `cloudwatch`. |
| `LOGS_EXPORT_DIR` | — | Output directory for `dir` target. |
| `LOGS_EXPORT_FILENAME` | `{{.container_name}}-{{.log_group}}.log` | Gomplate template for exported filenames. |
| `LOGS_OUTPUT_FORMAT` | `logfmt` | Also `json`. |
| `LOGS_GID` | `1084` (vector group) | GID for exported log files. |
| `DESKPRO_LOG_LEVEL` | `warning` | Application log level. |
| `DESKPRO_LOG_LEVEL_EMAIL_COLLECTION` | `warning` | |
| `DESKPRO_LOG_LEVEL_EMAIL_PROCESSING` | `warning` | |
| `PHP_FPM_LOG_LEVEL` | `notice` | |
| `NGINX_ERROR_LOG_LEVEL` | `warn` | |
| `BOOT_LOG_LEVEL` | `INFO` | Entrypoint log level to stderr (service modes). |
| `BOOT_LOG_LEVEL_EXEC` | `WARNING` | Entrypoint log level for `exec` / `bash`. |

See [reference/logging.md](./logging.md).

## Observability

| Variable | Default | Purpose |
| --- | --- | --- |
| `DESKPRO_ENABLE_NEWRELIC` | `false` | |
| `DESKPRO_NR_LICENSE` | — | New Relic license key. |
| `DESKPRO_NR_APP_NAME` | `Deskpro` | |
| `DESKPRO_NR_DAEMON_ADDRESS` | — | External New Relic daemon address. |
| `DESKPRO_NR_INI_OVERRIDES` | — | Extra `php.ini` for the New Relic extension. |
| `DESKPRO_NR_INSTRUMENT_BROWSER` | `false` | |
| `DESKPRO_ENABLE_OTEL` | `false` | OpenTelemetry. |
| `DESKPRO_SENTRY_FRONTEND_DSN` / `_BACKEND_DSN` / `_DEPRECATED_BACKEND_DSN` | — | Sentry error tracking. |
| `METRICS_ENABLED` | `false` | Exposes metrics on port 10001. |
| `METRICS_AUTH_BEARER_TOKEN` | — | Optional bearer auth for metrics. |
| `METRICS_NGINX_ENABLED` / `METRICS_PHP_FPM_ENABLED` | `true` / `true` | Individual metrics sources. |

## Healthcheck

| Variable | Purpose |
| --- | --- |
| `HEALTHCHECK_TEST_DB_CONNECTION` | If truthy, healthcheck verifies DB connectivity. |
| `HEALTHCHECK_TEST_DISCOVER` | If truthy, healthcheck hits the Deskpro discover endpoint. |

## App config

| Variable | Purpose |
| --- | --- |
| `DESKPRO_CONFIG_FILE` | Base template for the Deskpro PHP config. Default built-in. |
| `DESKPRO_CONFIG_EXTENSIONS` | Colon-delimited list of extra config files to append. |
| `DESKPRO_CONFIG_RAW_PHP` | Raw PHP appended to the final config. Escape hatch. |
| `DESKPRO_API_BASE_URL_PRIVATE` | Internal API URL. Default `http://127.0.0.1:80`. When localhost, triggers nginx+FPM auto-start in task modes. |
| `CUSTOM_MOUNT_BASEDIR` | Operator mount root. Default `/deskpro`. |

## Control

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONTAINER_NAME` | — | Human-readable tag used in logs. |
| `FAST_SHUTDOWN` | `false` | Skip graceful-shutdown waits. |
| `NO_SHUTDOWN_ON_ERROR` | `false` | Keep container alive if a service fails. Debug only. |
| `DISABLE_CLEAN_VARS` | `false` | Skip the env-var cleanup step. Debug only. |
| `CRON_STATUS_FILEPATH` | `/run/deskpro-cron-status.json` | Where `tasksd` writes its status. |

## Licensing (single-tenant)

| Variable | Purpose |
| --- | --- |
| `DESKPRO_TENANT_ID` | Tenant identifier. |
| `DESKPRO_LICENSE_KEY` | Hard-coded license, overrides in-product licensing. |
| `DESKPRO_LICENSE_KEY_INSTALL` | License to install on first boot. |
| `DESKPRO_SVC_KEY` | Service key for multi-tenant context-less operations. |
| `DESKPRO_CLOUD_MODE` | `false`. Multi-tenant mode. Kept in process env (`setEnv: true`). |

## Testing / development

| Variable | Purpose |
| --- | --- |
| `DESKPRO_DEBUG_MODE` | `false`. Enables verbose app-level debug output. |
| `DESKPRO_ENABLE_TEST_HEADER` | `false`. Enables a test HTTP header. |
| `DESKPRO_ENABLE_TEST_SUPPORT` | `false`. Adds test-only endpoints. |
| `DESKPRO_TEST_RESET_DB_SCRIPT` | Custom DB-reset script for test harnesses. |
| `DESKPRO_DISABLE_TELEMETRY` | `false`. Disables product telemetry. |
