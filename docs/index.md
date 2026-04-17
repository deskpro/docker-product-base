---
title: docker-product-base — documentation index
type: reference
last_reviewed: 2026-04-17
status: current
---

# docker-product-base — documentation index

`docker-product-base` is the base Docker image for the Deskpro product. It provides the runtime (Debian, PHP-FPM, nginx, supervisor, vector, helper scripts, templated configs, multi-mode entrypoint) on top of which the application image is built.

[↑ Back to the repo README](../README.md)

## Tutorials

Learning-oriented. For someone new to this.

*No tutorials yet.*

## How-to guides

Task-oriented. For someone who knows what they're trying to do.

- [Run Deskpro with Docker Compose](./how-to/run-with-docker-compose.md) — stand up the full stack locally.
- [Run background tasks in dedicated containers](./how-to/run-background-tasks-separately.md) — split email services out from the generic tasks loop.
- [Update a Deskpro deployment](./how-to/update-deskpro.md) — pull, back up, migrate, restart.
- [Configure Deskpro behind a reverse proxy](./how-to/configure-reverse-proxy.md) — X-Forwarded-*, PROXY protocol, Cloudflare.
- [Enable HTTPS on the built-in web server](./how-to/enable-https.md) — mounting a cert, the testing cert warning, custom CAs, MySQL TLS.
- [Debug a running Deskpro container](./how-to/debug-a-running-container.md) — logs, shell, `container-var`, manual job invocation.

## Reference

Information-oriented. For looking things up.

- [Environment variable reference](./reference/environment-variables.md) — curated index over `container-var-reference.json`.
- [Run modes](./reference/run-modes.md) — `web`, `tasks`, `email_collect`, `email_process`, `combined`, `svc`, `none`, `bash`, `exec`.
- [Ports and mount conventions](./reference/ports-and-mounts.md) — EXPOSE'd ports, `/deskpro/` layout, sentinel files.
- [Helper CLIs bundled in the image](./reference/helper-scripts.md) — `container-var`, `healthcheck`, `is-ready`, `mysql-*`, `phpinfo`, `phpfpminfo`.
- [Logging reference](./reference/logging.md) — vector, logfmt/JSON, boot log, custom sinks.

## Explanation

Understanding-oriented. For context and rationale.

- [Architecture overview](./explanation/architecture.md) — layers, runtime components, how the product image layers on top.
- [Container boot flow](./explanation/boot-flow.md) — what the entrypoint does, in order, and failure modes at each step.
- [How configuration reaches the application](./explanation/configuration-flow.md) — env vars, templates, mounted files, and their precedence.

## Sub-domains

Sub-directories of this repo that have their own docs:

- [`test/`](../test/README.md) — the Earthly + Serverspec test harness and the mock Deskpro app used to drive it.

## Decisions

*No ADRs yet.* Add architecture decision records under [`decisions/`](./decisions/) when you make a choice that future contributors will need to understand.

## External resources

- [Public release notes](https://github.com/deskpro/docker-product-base/releases) — what changed in each container version.
- [Customer-facing deployment guides](https://support.deskpro.com/en-US/guides/deskpro-private-controller) — install, configure, operate. Aimed at users of the *product* image, not maintainers of *this* repo.
- [`deskpro/docker-compose-example`](https://github.com/deskpro/docker-compose-example) — reference Compose stack.
