# test/

This directory is the test harness for the base image. It's an [Earthly](https://earthly.dev/)-orchestrated [Serverspec](https://serverspec.org/) suite that builds the image, spins up containers in various configurations, and asserts correctness from inside the running container.

It is its own domain inside this repo — with its own docs under [`docs/`](./docs/index.md) — because its contents (Ruby specs, a mock Deskpro app, Earthly targets) are unlike the rest of the repo.

## Quick start

Run every test:

```bash
earthly -P +test
```

Run one target:

```bash
earthly -P +test-serverspec-web          # Pristine web-mode tests
earthly -P +test-autoinstall             # AUTO_RUN_INSTALLER=true
earthly -P +test-custom-configs          # Mounted config files
# See test/Earthfile for the full list, or docs/reference/earthly-targets.md
```

Build and save the test image so you can inspect it manually:

```bash
earthly -P +save-base-image              # Tags deskpro/docker-product-base:test
docker run --rm -it deskpro/docker-product-base:test bash
```

All targets require [Earthly](https://earthly.dev/get-earthly) and Docker. The `-P` flag grants privileged mode (needed for Docker-in-Docker).

## Documentation

- Documentation index: [`docs/index.md`](./docs/index.md)
- Repo-wide context: [`../AGENTS.md`](../AGENTS.md) and [`../docs/index.md`](../docs/index.md)
