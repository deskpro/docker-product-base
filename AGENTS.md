# AGENTS.md

## What this is

This repo builds `deskpro/docker-product-base` — the base Docker image that the Deskpro product image extends. It bundles Debian 13, PHP 8.3, nginx, supervisor, vector (for logs), gomplate (for templating), and a set of Deskpro-specific helper scripts, templated configs, and an entrypoint that supports multiple run modes (web, tasks, email collect/process, etc.). The Deskpro application itself is NOT in this image — it is layered on top.

## Running tests and linters

- Tests: `earthly -P +test` (runs the full Serverspec suite in Earthly)
- Individual test targets: `earthly -P +test-serverspec-web`, `+test-serverspec-opc`, `+test-autoinstall`, `+test-automigrations`, `+test-custom-configs`, `+test-custom-logs-group`, `+test-serverspec-simple-cases`
- Build locally (no tests): `docker build -t deskpro/docker-product-base:dev .`
- Lint: there is no dedicated linter. The Dockerfile is hand-maintained.

Tests live in [`test/serverspec/`](./test/serverspec/) and the Earthfile that drives them is at [`test/Earthfile`](./test/Earthfile).

## Conventions

- Follow the company [coding standards](https://github.com/deskpro/deskpro-docs/blob/main/reference/coding-standards.md).
- **Templating**: any file under `/etc/{nginx,php,supervisor,vector}` with a `.tmpl` suffix is processed by [gomplate](https://docs.gomplate.ca/) at boot by `entrypoint.d/40-evaluate-configs.sh`. Do not reference env vars directly in the rendered file paths — put the `.tmpl` version in the image and let the entrypoint render it.
- **Environment variables** are documented in a single source of truth: [`usr/local/share/deskpro/container-var-reference.json`](./usr/local/share/deskpro/container-var-reference.json). Every new env var MUST be added there with `name`, `description`, `default`, `isPrivate`, and `setEnv` fields. Private vars are moved to `/run/container-config/` and stripped from the environment by `10-container-config.sh`.
- **Entrypoint scripts** in [`usr/local/sbin/entrypoint.d/`](./usr/local/sbin/entrypoint.d/) run in filename order — the numeric prefix (`00-`, `10-`, `20-`, …) matters. Never remove the prefix.
- **Users**: application code runs as `dp_app` (UID 1083), nginx as `nginx` (1085), vector as `vector` (1084, member of `adm` so it can read logs). Never introduce code paths that require root at runtime.
- **Services** are enabled/disabled through `SVC_*_ENABLED` env vars set by `15-run-mode.sh` based on the container's `CMD` argument. Do not hard-code `autostart=true` in supervisor configs — read the `SVC_*_ENABLED` var.
- **Helper CLIs** in [`usr/local/bin/`](./usr/local/bin/) are user-facing (available in `exec`/`bash` mode). `usr/local/sbin/` is for internal scripts only.

## Important docs

- Documentation index: [`docs/index.md`](./docs/index.md)
- Architecture overview: [`docs/explanation/architecture.md`](./docs/explanation/architecture.md)
- Boot flow (what the entrypoint does, in order): [`docs/explanation/boot-flow.md`](./docs/explanation/boot-flow.md)
- Environment variable reference: [`docs/reference/environment-variables.md`](./docs/reference/environment-variables.md)
- Run modes: [`docs/reference/run-modes.md`](./docs/reference/run-modes.md)
- Ports and volume mount conventions: [`docs/reference/ports-and-mounts.md`](./docs/reference/ports-and-mounts.md)
- Helper CLIs: [`docs/reference/helper-scripts.md`](./docs/reference/helper-scripts.md)
- Runbooks: [`docs/runbooks/`](./docs/runbooks/)

Working inside `test/`? It has its own [`AGENTS.md`](./test/AGENTS.md) with directory-specific conventions.

## Do not touch without human review

- `Dockerfile` — GPG fingerprints, package versions, and stage ordering are security-sensitive. Bumping a version is fine but always confirm the change with a human before pushing.
- `usr/local/share/deskpro/container-var-reference.json` — schema changes propagate to the product image and downstream tooling. Add fields, don't rename or remove.
- `usr/local/sbin/entrypoint.sh` and anything in `usr/local/sbin/entrypoint.d/` — the startup contract with the product image. Changes here can break every deployment.
- `etc/nginx/conf.d/` — routing and proxy-protocol handling. Breakage here is visible to customers immediately.
- `hooks/` — Docker Hub automated build hooks.
- Anything referencing certificates under `/etc/ssl/` or `/deskpro/ssl/`.
