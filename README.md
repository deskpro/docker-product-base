# docker-product-base

This is the source for the base Docker image used by Deskpro product. It provides the runtime (Debian, nginx, PHP-FPM, supervisor, vector, helper CLIs, templated configs) on top of which the Deskpro application image is built. It is published to Docker Hub at [`deskpro/docker-product-base`](https://hub.docker.com/r/deskpro/docker-product-base).

> This is only a base image and does NOT include the Deskpro application itself. To run Deskpro, use the full product image — see [support.deskpro.com/guides/topic/1841](https://support.deskpro.com/guides/topic/1841).

## Quick start

Build locally:

```bash
docker build -t deskpro/docker-product-base:dev .
```

Run the test suite (requires [Earthly](https://earthly.dev/)):

```bash
earthly -P +test
```

Run a single test target:

```bash
earthly -P +test-serverspec-web
```

## Owner

Platform / Infrastructure. Issues and suggestions go to the [GitHub issue tracker](https://github.com/deskpro/docker-product-base/issues). Questions about the Deskpro product itself should go to [Deskpro support](https://support.deskpro.com/new-ticket).

## Documentation

- Repository docs: [`docs/index.md`](./docs/index.md)
- End-user guides for running the product image: [support.deskpro.com](https://support.deskpro.com/en-US/guides/deskpro-private-controller)
