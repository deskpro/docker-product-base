---
title: Helper CLIs bundled in the image
type: reference
last_reviewed: 2026-04-17
status: current
---

# Helper CLIs bundled in the image

The image bundles a set of utility commands under `/usr/local/bin/` that are on `PATH` in every shell. They're aimed at operators debugging a running container, but they're also used by the entrypoint scripts.

## `container-var`

Reads a container variable. Checks the environment first, then `/run/container-config/<VAR>`, then the default declared in `container-var-reference.json`.

```bash
container-var DESKPRO_DB_HOST              # Print the value (or default)
container-var DESKPRO_DB_PASS              # Works even for private vars (not in env)
container-var --required DESKPRO_ES_URL    # Exit 33 if unset, 34 if empty
container-var --not-empty DESKPRO_DB_HOST
container-var --default fallback DESKPRO_FOO
container-var --ignore-env DESKPRO_DB_HOST # Skip the env check
container-var --debug DESKPRO_DB_HOST      # Show lookup trace on stderr
```

Use this from shell scripts, entrypoint hooks, or interactive debugging — never re-derive a value from a `/run/container-config/` file by hand.

## `print-container-vars`

Prints every container variable and its current value — useful for a snapshot during triage. Sources them first so private vars appear too.

```bash
print-container-vars | grep DESKPRO_DB
```

## `eval-tpl`

Wrapper around `gomplate` that pre-loads every container variable into the environment before invoking it. Used internally by the template evaluation step; useful for testing a template:

```bash
eval-tpl -f my-template.tmpl -o my-rendered-output
```

## `healthcheck`

The Docker HEALTHCHECK command calls this. You can invoke it manually for a quick status:

```bash
healthcheck                     # Default: check if services respond
healthcheck --wait              # Block until healthy
healthcheck --timeout 30        # Give up after 30s
healthcheck --test-ready        # Also require container-ready sentinel
healthcheck --test-http         # Hit the internal HTTP endpoint
healthcheck --test-db           # Verify DB connectivity
healthcheck --test-discover     # Verify Deskpro discover endpoint
```

Exit `0` means healthy. Non-zero means one of the requested tests failed.

## `is-ready`

Lighter than `healthcheck`. Returns `0` once the entrypoint has finished boot tasks (installer / migrations done, services started). Useful in orchestration layers that need to wait before sending traffic.

```bash
is-ready --wait --timeout 120
is-ready --check-tasks          # Also require the task scheduler is alive
is-ready -v                     # Verbose mode
```

## `mysql-primary` / `mysql-read` / `mysqldump-primary`

Thin wrappers around the `mysql` client. They read the same DB credentials Deskpro uses (from container vars) so you don't have to pass host / user / password.

```bash
mysql-primary                                   # Interactive client, writeable
mysql-read                                      # Interactive, read-replica if configured, else read-only
mysql-read -e 'SELECT * FROM people WHERE is_agent=1'
mysqldump-primary --hex-blob --single-transaction deskpro > dump.sql
```

Any extra argument is passed through to the underlying tool. The wrappers write a `~/.my-auto.cnf` on first use and invoke the real client with `--defaults-group-suffix=_primary` or `_read`.

Prefer `mysql-read` for read queries; it will use the read replica if one is configured, and otherwise puts the session into read-only mode.

## `phpinfo`

Prints `phpinfo()` output. Supports both CLI and FPM contexts:

```bash
phpinfo              # CLI SAPI
phpinfo --fpm        # Ask an FPM pool for its view (useful for verifying pool config)
```

## `phpfpminfo`

Dumps the resolved PHP-FPM pool configuration — handy when you've used `PHP_FPM_*_OVERRIDES` and want to see what actually took effect.

```bash
phpfpminfo                       # All pools
phpfpminfo --pool dp_default     # One pool
```

## Not on PATH — but useful to know exist

- [`/usr/local/sbin/entrypoint.sh`](../../usr/local/sbin/entrypoint.sh) — the boot orchestrator.
- [`/usr/local/sbin/container-ready.sh`](../../usr/local/sbin/container-ready.sh) — supervisord one-shot task that waits for services then runs installer/migrations.
- [`/usr/local/sbin/tasksd`](../../usr/local/sbin/tasksd) — the cron loop used by the `tasks` mode. Respects `/deskpro/config/PAUSE_CRON`.
