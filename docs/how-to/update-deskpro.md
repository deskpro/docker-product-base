---
title: Update a Deskpro deployment
type: how-to
last_reviewed: 2026-04-17
status: current
---

# Update a Deskpro deployment

This is the manual update procedure for deployments that run the product image directly (not via the DPC). Follow the same general steps whether you use `docker run`, Compose, Kubernetes, or ECS — the commands differ but the sequence doesn't.

## The sequence

1. Pull the new image tag.
2. Stop the running Deskpro containers.
3. Back up the database.
4. Run migrations with the new image.
5. Restart containers on the new tag.

Database changes in step 4 are one-way. If a migration fails, restore from the backup in step 3 before starting the old version again.

## Picking a version

Product images are tagged `<DPVERSION>-onprem-<CONTAINER_VERSION>`:

- `<DPVERSION>` — Deskpro product version, e.g. `2025.3.6`. New versions ship weekly.
- `onprem` — signals these are the images you should use (not the DPC-managed ones).
- `<CONTAINER_VERSION>` — semver of this base image. A major bump means a breaking change — read [the changelog on GitHub](https://github.com/deskpro/docker-product-base/releases) before applying.

Watch for announcements on the [Deskpro releases page](https://support.deskpro.com/en-US/news/release-announcements) or the [`deskpro/deskpro-product` Docker Hub tags](https://hub.docker.com/r/deskpro/deskpro-product/tags).

## `docker run` example

```bash
DPVERSION=2025.3.6
CONTAINER_VERSION=4.0.0
IMAGE=deskpro/deskpro-product:${DPVERSION}-onprem-${CONTAINER_VERSION}

# 1. Pull the new image
docker pull $IMAGE

# 2. Stop current containers
docker stop deskpro_web deskpro_tasks
docker rm deskpro_web deskpro_tasks

# 3. Back up the database
docker run --rm --env-file=config.env \
    -v "$PWD/db-backup:/db-backup" \
    $IMAGE \
    exec bash -c 'mysqldump-primary --hex-blob --lock-tables=false --single-transaction > /db-backup/pre-upgrade.sql'

# 4. Run migrations using the new image
docker run --rm --env-file=config.env \
    $IMAGE \
    exec tools/migrations/artisan migrations:exec -vvv --run

# 5. Start on the new image
docker run -d --name deskpro_web --env-file=config.env -p 80:80 $IMAGE web
docker run -d --name deskpro_tasks --env-file=config.env $IMAGE tasks
```

## Docker Compose

Update the image tag in your compose file, then:

```bash
docker compose pull
docker compose stop web tasks email
docker compose run --rm tasks \
    exec bash -c 'mysqldump-primary --hex-blob --lock-tables=false --single-transaction > /db-backup/pre-upgrade.sql'
docker compose run --rm tasks \
    exec tools/migrations/artisan migrations:exec -vvv --run
docker compose up -d
```

Mount a `./db-backup` volume on the `tasks` service so the dump ends up on disk.

## Verification

After restart, confirm readiness before sending traffic:

```bash
docker exec deskpro_web is-ready --wait --timeout 120
docker exec deskpro_web healthcheck --test-http --test-db
```

Check that migrations finished successfully — the output of the `migrations:exec` step is the authoritative signal. A failure there means the DB is in an indeterminate state and you should restore from backup.

## Rolling back

If you need to go back:

1. Stop containers.
2. Restore the DB from the pre-upgrade dump.
3. Restart on the previous tag.

There is no in-place downgrade — running old code against a migrated DB is unsupported.
