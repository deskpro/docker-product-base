# AGENTS.md — test/

## What this is

The test harness for `docker-product-base`. Earthly drives Docker-in-Docker builds; inside the built image, a Ruby [Serverspec](https://serverspec.org/) suite exec's against the running container to assert state. A tiny PHP "simulate-release" project under [`simulate-release/`](./simulate-release/) stands in for the real Deskpro app so tests can run without the private product image.

This AGENTS file inherits conventions from the [repo-root AGENTS.md](../AGENTS.md) — read that first. What follows is specific to this directory.

## Running tests

- Whole suite: `earthly -P +test`
- Single target: `earthly -P +test-<name>` (see the `+test` orchestration block in [`Earthfile`](./Earthfile) for the complete list)
- Local image for inspection: `earthly -P +save-base-image` → `deskpro/docker-product-base:test`

`-P` is required because the targets use Docker-in-Docker.

There is no separate linter for Ruby here — style is enforced by convention, not tooling.

## Conventions specific to this directory

- **One spec file per behaviour.** Use numeric prefixes (`01_...`, `02_...`) only in scenario directories where order matters (e.g. `01_installer_spec.rb` runs before `02_post_installer_spec.rb` across a container restart).
- **Every spec starts with `system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise`** in a `before(:all)` block. Without it, specs race the container's boot.
- **Clean up in `after(:all)`.** Specs share a container across examples, so leftover env vars or files will leak into the next spec.
- **Use Serverspec resource matchers** (`describe file(...)`, `describe user(...)`, `describe port(...)`) for anything they cover; drop to `describe command(...)` only for things they don't.
- **Fixtures live next to the scenario.** If a test needs a `/deskpro/config/` mount, put the contents under `serverspec/spec/scenarios/<name>/deskpro_dir/` and reference it from the Earthfile target — don't stash it elsewhere.
- **Mock responses in `simulate-release/sim.php`.** New simulated CLI commands and HTTP endpoints go there, not in a new file.

## Important docs

- Documentation index: [`docs/index.md`](./docs/index.md)
- How the harness works end-to-end: [`docs/explanation/test-harness.md`](./docs/explanation/test-harness.md)
- Every Earthly target in one place: [`docs/reference/earthly-targets.md`](./docs/reference/earthly-targets.md)
- What simulate-release is and how to extend it: [`docs/reference/simulate-release.md`](./docs/reference/simulate-release.md)
- Adding a new test: [`docs/how-to/add-a-new-test.md`](./docs/how-to/add-a-new-test.md)
- Iterating on a failing test: [`docs/how-to/debug-a-failing-test.md`](./docs/how-to/debug-a-failing-test.md)

## Do not touch without human review

- `Earthfile` — changing the target structure affects CI and local development for everyone. Small additions are fine; restructuring needs a human.
- `simulate-release/sim.php` — the contract between the harness and the real product image. Adding endpoints or commands is fine; renaming or removing existing ones breaks tests that already assume them.
- `serverspec/spec/always/` — these are the "must always be true" invariants of the image. Don't loosen an assertion to make a test pass; fix the root cause.
