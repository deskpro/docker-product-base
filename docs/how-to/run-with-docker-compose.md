---
title: Run Deskpro with Docker Compose
type: how-to
last_reviewed: 2026-04-17
status: current
---

# Run Deskpro with Docker Compose

This is for developers working on this base image who want to stand up the full product stack for testing. It is NOT the customer-facing guide.

The maintained, customer-facing compose project is [`deskpro/docker-compose-example`](https://github.com/deskpro/docker-compose-example). Start from there unless you have a specific reason to build your own.

## Quick start with the example repo

```bash
git clone https://github.com/deskpro/docker-compose-example.git
cd docker-compose-example

cp config.env.example config.env
vim config.env                    # set DESKPRO_APP_KEY, DB creds, ES URL

docker compose up -d
docker compose exec tasks bin/install --url 'http://127.0.0.1/' \
    --admin-email 'you@example.com' --admin-password 'hunter2'
```

## Using this repo's image instead of a published one

If you're iterating on this base image, override the product image in the compose file to use a locally-built variant of the product that's been rebased on your branch:

```yaml
services:
  web:
    image: deskpro/deskpro-product:local-onprem
    # ...
```

To build a local base image:

```bash
docker build -t deskpro/docker-product-base:dev .
```

Then rebuild the product image `FROM` that tag.

## Minimum compose skeleton

If you're building from scratch, the minimum shape is two Deskpro containers plus their external dependencies. Remember: the product image is `deskpro/deskpro-product:<DPVERSION>-onprem-<CONTAINER_VERSION>`, not `deskpro/docker-product-base` (which is only the base layer).

```yaml
services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: deskpro
      MYSQL_DATABASE: deskpro
    volumes: [mysql:/var/lib/mysql]

  elastic:
    image: elasticsearch:8.8.2
    environment:
      discovery.type: single-node
      xpack.security.enabled: "false"
    volumes: [es:/usr/share/elasticsearch/data]

  web:
    image: deskpro/deskpro-product:2025.3.6-onprem-4.0.0
    command: web
    env_file: config.env
    ports: ["80:80"]
    depends_on: [mysql, elastic]

  tasks:
    image: deskpro/deskpro-product:2025.3.6-onprem-4.0.0
    command: tasks
    env_file: config.env
    depends_on: [mysql, elastic]

volumes:
  mysql:
  es:
```

## Things to know

- Deskpro requires MySQL ≥ 8.0 and Elasticsearch 7.10–8.8 (or OpenSearch 1.8.x).
- Pin the image to `<DPVERSION>-onprem-<CONTAINER_VERSION>`, never `latest` — you need to control upgrade timing.
- Put secrets (`DESKPRO_DB_PASS`, etc.) into a file-based secret or an env file with `0600` perms, not directly in `docker-compose.yml`.
- The `tasks` service needs the same `env_file` as `web` so it can reach the DB and Elasticsearch.

Run-mode-specific guidance:

- Scale `web` horizontally behind a load balancer.
- Keep `tasks` at a single replica (cron does not coordinate across replicas).
- For high mail volume, add dedicated `email_collect` and `email_process` services — see [run-background-tasks-separately.md](./run-background-tasks-separately.md).
