---
title: test/ — documentation index
type: reference
last_reviewed: 2026-04-17
status: current
---

# test/ — documentation index

The test harness for `docker-product-base`: Earthly-driven Docker-in-Docker builds running a Serverspec suite against the built image.

[↑ Back to test/ README](../README.md) · [↑ Back to the repo-wide index](../../docs/index.md)

## Tutorials

Learning-oriented. For someone new to this.

*No tutorials yet.*

## How-to guides

Task-oriented. For someone who knows what they're trying to do.

- [Add a new test](./how-to/add-a-new-test.md) — where to put a spec, how to wire it into an Earthly target.
- [Debug a failing test](./how-to/debug-a-failing-test.md) — iterate quickly without rebuilding the world.

## Reference

Information-oriented. For looking things up.

- [Earthly targets](./reference/earthly-targets.md) — every target in `Earthfile`, what it exercises, how long it takes.
- [simulate-release](./reference/simulate-release.md) — the mock PHP app that stands in for the Deskpro product image.

## Explanation

Understanding-oriented. For context and rationale.

- [How the test harness works](./explanation/test-harness.md) — the end-to-end pipeline from `earthly +test` to RSpec output.

## Runbooks

*No runbooks yet.*

## Decisions

*No ADRs yet.*
