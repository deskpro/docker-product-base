---
title: Logging reference
type: reference
last_reviewed: 2026-04-17
status: current
---

# Logging reference

The container ships [vector](https://vector.dev/) as its log collector. Vector tails every service's log file, normalises lines into a single structured format, and writes them out to the chosen target.

## Output targets

Set by `LOGS_EXPORT_TARGET`:

| Target | Behaviour |
| --- | --- |
| `stdout` | Write to the container's stdout. The default when `/deskpro/logs/` is not mounted. |
| `dir` | Write files into `LOGS_EXPORT_DIR`. Auto-selected when `/deskpro/logs/` is mounted. |
| `cloudwatch` | Ship to Amazon CloudWatch Logs. |

In `exec` and `bash` run modes, the default target is `dir` with `LOGS_EXPORT_DIR=/var/log/docker-logs` (inside the container), so stdout stays clean for interactive use. Mount `/deskpro/logs/` if you want those logs externalised.

## Output format

`LOGS_OUTPUT_FORMAT` chooses between:

- `logfmt` (default): `ts=... app=... lvl=... msg="..."` on one line per event.
- `json`: same fields, JSON-encoded.

## Fields

Every line carries these normalised fields:

| Field | Meaning |
| --- | --- |
| `ts` | UTC timestamp, ISO 8601. |
| `app` | Source — `entrypoint`, `supervisord`, `nginx`, `php`, `php_fpm`, `deskpro`, `deskpro-dpv5`, `deskpro-tasks`. |
| `chan` | Channel within an app — `access`, `error`, `general`, `migrations`, `errors`, etc. |
| `lvl` | `DEBUG`, `INFO`, `WARNING`, `ERROR`. |
| `msg` | The message. |
| `container_name` | `CONTAINER_NAME` env var, if set. |
| `log_group` | Used in `LOGS_EXPORT_FILENAME` templating. |

App-specific fields (e.g. request path, method, status) appear as-is on the same line.

## When logs go to `dir`

Files are named by the `LOGS_EXPORT_FILENAME` template (default `{{.container_name}}-{{.log_group}}.log`). Files are owned by `root:<LOGS_GID>` (default GID `1084`, the `vector` group) so you can control access by making the host directory owned by the group you want and setting the sticky bit:

```bash
mkdir container-logs
chown root:mygroup container-logs
chmod g+s container-logs
```

**Rotation is your responsibility on the host.** Vector does not rotate exported files.

## Boot log

The entrypoint's own log (`app=entrypoint`) is special because vector itself might not yet be running. It's always written to `/var/log/docker-boot.log` inside the container AND emitted to stderr, filtered by:

- `BOOT_LOG_LEVEL` (default `INFO`) — minimum level printed to stderr in service modes.
- `BOOT_LOG_LEVEL_EXEC` (default `WARNING`) — minimum level in `exec` / `bash` modes.

If exported logs are enabled, `docker-boot.log` will also appear in the export directory.

## Customising vector

Mount a custom config file at `/deskpro/config/vector.d/99-my-output.toml`. Two stable named inputs are available for custom sinks:

- `all` — every log event as a structured record, with a normalised `.logprops` object carrying `app`, `chan`, `lvl`, `msg`, and any extras.
- `all_formatted` — every event with a pre-rendered `.message` string in the current `LOGS_OUTPUT_FORMAT`. Convenient for sinks with `encoding.codec = "raw_message"`.

Avoid referencing the internal source names (e.g. specific `file` sources) directly — they may change between versions. Filter `all` by `.app`, `.chan`, or `.lvl` instead.

Example: ship everything through an HTTP sink in JSON:

```toml
# /deskpro/config/vector.d/99-my-http.toml
[sinks.my_http]
type = "http"
inputs = ["all"]
uri = "https://logs.example.internal/ingest"
encoding.codec = "json"
```

## Log levels

| Variable | Default |
| --- | --- |
| `DESKPRO_LOG_LEVEL` | `warning` |
| `DESKPRO_LOG_LEVEL_EMAIL_COLLECTION` | `warning` |
| `DESKPRO_LOG_LEVEL_EMAIL_PROCESSING` | `warning` |
| `PHP_FPM_LOG_LEVEL` | `notice` |
| `NGINX_ERROR_LOG_LEVEL` | `warn` |
