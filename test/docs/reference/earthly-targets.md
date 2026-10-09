---
title: Earthly targets
type: reference
last_reviewed: 2026-04-17
status: current
---

# Earthly targets

All targets are defined in [`Earthfile`](../../Earthfile). Invoke with `earthly -P +<target>` from the repo root. The `-P` flag enables privileged mode (required for Docker-in-Docker).

The repo-root [`Earthfile`](../../../Earthfile) only builds the production image — it does NOT delegate to this one. That's intentional: running the full test suite is opt-in.

## Top-level targets

| Target | What it does |
| --- | --- |
| `+test` | Runs every test target. Uses `WAIT` blocks to parallelise where safe: serverspec, opc, simple-cases, custom-configs, custom-logs-group, and smokescreen in one wave; autoinstall next; automigrations last. |
| `+save-base-image` | Builds the test-flavoured image (`+base-image`) and tags it `deskpro/docker-product-base:test` locally. Use this to poke at the test image interactively with `docker run -it deskpro/docker-product-base:test bash`. |
| `+base-image` | Internal. Builds the production image and layers Ruby + serverspec + the mock app on top. Every other target inherits from it. |

## Serverspec targets

| Target | Specs exercised | Setup |
| --- | --- | --- |
| `+test-serverspec-web` | `spec/always/`, `spec/default_web/` | None beyond the base image. Runs twice, separated by a restart. |
| `+test-serverspec-opc` | `spec/scenarios/bc_opc_2_8/01_opc_bc.rb` + `spec/always/` + `spec/default_web/` | Sets `OPC_VERSION=2.8.0`. Mounts `spec/scenarios/bc_opc_2_8/deskpro_dir` as `/deskpro` and `test_helper_tools` for config-value extraction. |
| `+test-serverspec-simple-cases` | `spec/cases/simple/*` | None. Runs once. |

## Scenario targets

| Target | Specs | Setup |
| --- | --- | --- |
| `+test-autoinstall` | `spec/scenarios/autoinstall/01_installer_spec.rb`, `02_post_installer_spec.rb` | Creates `/tmp/sim/needs-installer` sentinel, mounts it at `/run/sim`. Runs with `AUTO_RUN_INSTALLER=true`. First run: installer ran. After restart: it didn't re-run. |
| `+test-automigrations` | `spec/scenarios/automigrations/01_migrations_spec.rb`, `02_post_migrations_spec.rb` | Creates `/tmp/sim/needs-migrations` sentinel. Runs with `AUTO_RUN_MIGRATIONS=true`. First run: migrations ran. After restart: they didn't re-run. |
| `+test-custom-configs` | `spec/scenarios/custom_configs/01_custom_configs_spec.rb`, `02_custom_configs_removed_spec.rb` | Mounts `spec/scenarios/custom_configs/deskpro_dir` as `/deskpro`. First run: mounted configs (`99-custom.ini` and `99-custom_tmpl.ini.tmpl`) took effect. After removing them and restarting: their effects are gone. |
| `+test-custom-logs-group` | `spec/scenarios/custom_log_group/01_custom_log_group_spec.rb` | Creates a `logs_group` GID 1988 on the host, mounts `/tmp/deskpro-logs` as `/deskpro/logs` with that group, sets `LOGS_GID=1988`. Triggers a PHP error to generate log output, stops the container, verifies host-side ownership. |
| `+test-smokescreen` | `spec/scenarios/smokescreen/01_smokescreen_disabled_spec.rb`, `02_smokescreen_override_spec.rb`, `03_smokescreen_no_proxy_derivation_spec.rb`, `04_smokescreen_no_proxy_url_hosts_spec.rb`, `05_smokescreen_config_php_merge_spec.rb`, `06_smokescreen_config_php_nonzero_fallback_spec.rb`, `07_smokescreen_config_php_malformed_fallback_spec.rb`, `08_smokescreen_disable_false_spec.rb`, `09_smokescreen_svc_override_under_disable_spec.rb`, `10_smokescreen_svc_override_disabled_spec.rb`, `14_smokescreen_external_proxy_spec.rb`, `15_smokescreen_external_proxy_precedence_spec.rb` | Containers run with `DISABLE_DESKPRO_PROXY_SERVICE=false` unless noted (the default is off). `DISABLE_DESKPRO_PROXY_SERVICE=true` (daemon + proxy env vars both off); `SMOKESCREEN_CONFIG_FILE` pointing at a config mounted via `spec/scenarios/smokescreen/deskpro_dir/config/smokescreen.d/`; `DESKPRO_DB_HOST` plus an operator `NO_PROXY` entry (derived-default `NO_PROXY` list); `DESKPRO_ES_URL`/`DESKPRO_ES_TIKA_HOST`/`DESKPRO_REDIS_URL`/`OTEL_EXPORTER_OTLP_ENDPOINT` (URL-shaped backend vars, to cover the host-extraction path); three with a stub `/srv/deskpro/serve/bin/dump-cfg` mounted from `spec/scenarios/smokescreen/dump_cfg_fixtures/` (full JSON shape merged into `NO_PROXY`, a non-zero exit falling back, and non-JSON stdout falling back); `DISABLE_DESKPRO_PROXY_SERVICE=false` explicit (baseline, both on); `13_smokescreen_enabled_spec.rb` (enabled behaviour: loopback listener, egress classification, dump-cfg-absent no-op); `DISABLE_DESKPRO_PROXY_SERVICE=true` + `SVC_SMOKESCREEN_ENABLED=true` (operator override keeps the daemon up, env still off); `SVC_SMOKESCREEN_ENABLED=false` with `DISABLE_DESKPRO_PROXY_SERVICE=false` (operator override stops the daemon, env still on). `DESKPRO_HTTPS_PROXY` with smokescreen off (14: DESKPRO value in all four service configs, `NO_PROXY` derived, daemon off) and with smokescreen on (15: DESKPRO wins for the variable it covers, smokescreen remains fallback). Default-off behaviour is covered by `spec/cases/simple/smokescreen_spec.rb` instead, since it needs no special setup. |

## Running locally

```bash
# Full suite (takes ~5–10 minutes)
earthly -P +test

# Single target while iterating
earthly -P +test-serverspec-web

# Re-run without rebuilding when only specs changed
earthly -P --no-cache +test-serverspec-web
```

Earthly caches aggressively. If you've edited a spec file but see the old behaviour, pass `--no-cache` to force a rebuild. If only the Dockerfile or repo source changed, the cache will correctly invalidate on its own.

## Adding a new target

See [how-to/add-a-new-test.md](../how-to/add-a-new-test.md) for the full walkthrough. Short version:

1. Add a new block in `Earthfile` following the pattern of an existing scenario (e.g. `+test-custom-configs`).
2. Add a `BUILD +your-target` line under the appropriate `WAIT` block in `+test`.
3. Place your specs under `serverspec/spec/scenarios/<your-name>/` and any fixtures next to them.
