---
title: simulate-release — the mock Deskpro app
type: reference
last_reviewed: 2026-04-17
status: current
---

# simulate-release — the mock Deskpro app

[`simulate-release/`](../../simulate-release/) is a ~200-line PHP project that implements just enough of the Deskpro application surface for the test harness to exercise the base image without pulling in the private product image. At test build time, it's copied to `/srv/deskpro/` — the same path the real product image uses.

It is NOT a re-implementation of Deskpro. It implements the contract the entrypoint and the container's helper scripts rely on: a few HTTP endpoints, a few CLI commands, a dummy long-lived service.

## Layout

| Path | Purpose |
| --- | --- |
| [`sim.php`](../../simulate-release/sim.php) | The single PHP class implementing every simulated behaviour. |
| [`serve/www/index.php`](../../simulate-release/serve/www/index.php) | Web entrypoint — what nginx proxies to. |
| [`bin/install`](../../simulate-release/bin/install) | Installer CLI. The auto-installer runs this. |
| [`tools/fixtures/artisan`](../../simulate-release/tools/fixtures/artisan) | Mock fixtures runner. |
| [`tools/migrations/artisan`](../../simulate-release/tools/migrations/artisan) | Mock migrations runner. The auto-migrations path invokes this. |
| [`services/messenger-api/bin/start`](../../simulate-release/services/messenger-api/bin/start) | Dummy long-running service used by supervisor-management tests. |

## Simulated web endpoints

Served by nginx → PHP-FPM → `serve/www/index.php` → `DeskproSimulateRelease::runWeb()`.

| Path | Returns |
| --- | --- |
| `/` | `200 "Simulating source files"` — plus conditional status codes if sentinel files are present (see below). |
| `/phpinfo` | Full `phpinfo()` output. Useful for inspecting effective PHP settings under FPM. |
| `/api/v2/helpdesk/discover` | JSON matching the real discover endpoint's shape. Used by `healthcheck --test-discover`. |
| `/dump-config` | JSON dump of the Deskpro config PHP file, so tests can assert config-templating outcomes. |

### Conditional response codes

If `/run/sim/needs-installer` exists, the mock returns **500** — simulating a fresh, un-installed instance. If `/run/sim/needs-migrations` exists, it returns **423 Locked** — simulating an instance whose schema is out of date. Both go away when the test removes (or the auto-install / auto-migrations path deletes) the sentinel.

## Simulated CLI commands

| Command | Behaviour |
| --- | --- |
| `bin/install` | Sleeps briefly (respecting `SIM_INSTALL_WAIT`), exits 0. Simulates a successful install. |
| `tools/fixtures/artisan install` | Same as `bin/install`. |
| `tools/fixtures/artisan test:wait-db` | Exits 0. Simulates a "DB is ready" probe. |
| `tools/migrations/artisan migrations:status` | Exits `2` if `needs-installer` sentinel present (empty DB), `10` if `needs-migrations` (pending), `0` otherwise. |
| `tools/migrations/artisan migrations:exec` | Sleeps briefly, exits 0. |

The `services/messenger-api/bin/start` script is a shell loop that prints a heartbeat every 2 seconds — enough for supervisord to consider it "RUNNING".

## Sentinel files the harness uses

| File | Mounted by | Effect |
| --- | --- | --- |
| `/run/sim/needs-installer` | `+test-autoinstall` | `migrations:status` reports empty DB; web returns 500. |
| `/run/sim/needs-migrations` | `+test-automigrations` | `migrations:status` reports pending migrations; web returns 423. |

The Earthfile targets create these on the host and mount them at `/run/sim`.

## Extending it

Adding a new simulated command or endpoint is a two-step process:

1. Add the behaviour to `DeskproSimulateRelease` in [`sim.php`](../../simulate-release/sim.php). Match the pattern of existing commands — keep them small and return the exit code or HTTP status the real app would.
2. If the new behaviour has a different CLI entry point (different binary name), add a thin PHP wrapper under `bin/`, `tools/<name>/artisan`, or similar — mirroring the path the real product image uses.

Do NOT introduce new PHP dependencies. The mock is intentionally dependency-free so it runs under just the base image's PHP. If you need a library, ask whether the behaviour really belongs in the base-image test suite at all — it may fit better in the product repo.

## What NOT to put here

- Actual business logic from the product.
- Anything that requires a database.
- Deskpro-specific endpoint handlers.

If a test needs real app behaviour, it belongs in the product repo's own tests, not here.
