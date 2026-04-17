---
title: Run background tasks in dedicated containers
type: how-to
last_reviewed: 2026-04-17
status: current
---

# Run background tasks in dedicated containers

By default, the `tasks` run mode runs every type of background job in a single container: cron-scheduled tasks, queue workers, and email collection/processing. For larger deployments you'll want to separate email work into its own containers so it doesn't block cron, and so you can scale email independently.

## When to split

- Mail volume is high enough that email jobs crowd out other cron work.
- Your SLO for inbound email latency is tight and you want dedicated processes.
- You want to scale collect and process horizontally.

Running multiple generic `tasks` containers is also supported with no special setup — they deduplicate cron work automatically.

## Steps

**1. On every container's env, set `TASKS_DISABLE_EMAIL_IN_JOB=true`.** This stops the generic `tasks` run mode from also running the in-cron email job. It's safe to set everywhere (unused modes ignore it), so it's fine to put in your shared `config.env`.

```bash
TASKS_DISABLE_EMAIL_IN_JOB=true
```

**2. Run email services in dedicated containers** via `svc email_collect email_process`, or split them into two separate containers for more control:

```bash
docker run -d --name deskpro_email \
    --env-file config.env \
    deskpro/deskpro-product:$DPVERSION-onprem-$CONTAINER_VERSION \
    svc email_collect email_process
```

**3. Tune concurrency and timeouts** per container using the `SVC_EMAIL_*` variables. Only one process can read a single email account at a time, so `SVC_EMAIL_COLLECT_NUMPROCS` above the number of accounts wastes resources.

Collect:

```bash
SVC_EMAIL_COLLECT_NUMPROCS=2        # Processes per container
SVC_EMAIL_COLLECT_ARGS_EACH_MAX_TIME=30     # Max seconds per account
SVC_EMAIL_COLLECT_ARGS_TIMEOUT=45           # Hard timeout
SVC_EMAIL_COLLECT_ARGS_ACCOUNT_REST=15      # Delay between empty polls
```

Process:

```bash
SVC_EMAIL_PROCESS_NUMPROCS=2        # Each process ~512MB RAM
SVC_EMAIL_PROCESS_ARGS_TIMEOUT=300  # Per-message timeout
SVC_EMAIL_PROCESS_ARGS_TRIES=3      # Retry budget
```

**4. (Optional) Scale horizontally.** You can run multiple `email_collect` containers. Because only one process can poll any given account at a time, scaling beyond the number of accounts yields no throughput gain for collect — but you can still scale `email_process` up independently.

## Compose example

```yaml
services:
  web:
    image: deskpro/deskpro-product:2025.3.6-onprem-4.0.0
    command: web
    env_file: config.env

  tasks:
    image: deskpro/deskpro-product:2025.3.6-onprem-4.0.0
    command: tasks
    env_file: config.env
    environment:
      TASKS_DISABLE_EMAIL_IN_JOB: "true"

  email:
    image: deskpro/deskpro-product:2025.3.6-onprem-4.0.0
    command: svc email_collect email_process
    env_file: config.env
    environment:
      SVC_EMAIL_COLLECT_NUMPROCS: "2"
      SVC_EMAIL_PROCESS_NUMPROCS: "4"
    deploy:
      replicas: 2
```

## Verifying

```bash
docker exec deskpro_email supervisorctl status
# Should list email_collect and email_process as RUNNING
```

Or manually trigger a cycle from a shell to confirm the binary path works:

```bash
docker exec deskpro_email services/email-processing/artisan \
    email:collect-queue --max-time=60 --verbose
docker exec deskpro_email services/email-processing/artisan \
    email:process-queue --max-time=60 --verbose
```
