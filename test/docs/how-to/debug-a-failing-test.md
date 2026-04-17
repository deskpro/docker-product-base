---
title: Debug a failing test
type: how-to
last_reviewed: 2026-04-17
status: current
---

# Debug a failing test

The default Earthly output is terse. To actually understand why a spec fails, skip Earthly and drive the container directly.

## 1. Build the test image once

```bash
earthly -P +save-base-image
```

This tags `deskpro/docker-product-base:test` locally. Rebuild after any change to the Dockerfile or image-level files; you don't need to rebuild for changes under `test/serverspec/` (see step 4).

## 2. Start the container with the scenario's setup

Look at the target in [`Earthfile`](../../Earthfile) that's failing and reproduce its `docker run` line, substituting local paths:

```bash
# Example: reproducing +test-custom-configs
docker run -d --name dp-debug \
    -v "$PWD/test/serverspec/spec/scenarios/custom_configs/deskpro_dir:/deskpro" \
    deskpro/docker-product-base:test web
```

For scenarios that use `/run/sim` sentinels:

```bash
mkdir -p /tmp/sim && touch /tmp/sim/needs-installer
docker run -d --name dp-debug \
    -e AUTO_RUN_INSTALLER=true \
    -v /tmp/sim:/run/sim \
    deskpro/docker-product-base:test web
```

## 3. Wait for boot and check state

```bash
docker exec dp-debug /usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v
docker exec dp-debug supervisorctl status
docker logs dp-debug --tail=100
```

If boot failed, the entrypoint log is at `/var/log/docker-boot.log` inside the container:

```bash
docker exec dp-debug cat /var/log/docker-boot.log
```

## 4. Run the failing spec directly

This is the iteration loop. Edit the spec file on the host, then:

```bash
docker exec dp-debug /bin/sh -c 'cd /test/serverspec && rspec spec/scenarios/custom_configs/01_custom_configs_spec.rb'
```

When you change a spec on the host, the change isn't in the container. You have two options:

**Option A — copy the file in each time:**

```bash
docker cp test/serverspec/spec/cases/simple/my_spec.rb \
    dp-debug:/test/serverspec/spec/cases/simple/my_spec.rb
```

**Option B — bind-mount the serverspec tree when starting the container:**

```bash
docker run -d --name dp-debug \
    -v "$PWD/test/serverspec:/test/serverspec:ro" \
    ...
```

Option B is faster for rapid iteration. Remember to clean up and re-run through Earthly once you think it passes, because Earthly runs with a slightly different setup (baked-in specs, not bind-mounted).

## 5. Shell in for interactive debugging

```bash
docker exec -it dp-debug bash
```

From the shell, all the helper CLIs are available:

```bash
container-var DESKPRO_DB_HOST         # Read materialised env var
print-container-vars | grep PHP_      # Every PHP-related var
phpfpminfo --pool dp_default          # Resolved pool config
healthcheck --test-db --test-http
supervisorctl status
tail -f /var/log/nginx/error.log
```

See the repo-wide [debug how-to](../../../docs/how-to/debug-a-running-container.md) for the full toolbox.

## 6. Make the error more visible

If the spec failure message doesn't make the cause obvious:

- Drop `puts output` into the spec to print intermediate values.
- Run rspec with `--format documentation --backtrace` inside the container for a noisier output.
- Temporarily raise the boot log level: the test image already sets `BOOT_LOG_LEVEL=TRACE`, but you can also set `DESKPRO_LOG_LEVEL=debug` when starting the container to get verbose application logs.

## 7. Clean up

```bash
docker rm -f dp-debug
rm -rf /tmp/sim /tmp/deskpro-dir /tmp/deskpro-logs
```

## Common failure patterns

| Symptom | Likely cause |
| --- | --- |
| Spec intermittently fails | Missing the `is-ready --wait` preamble in `before(:all)`. |
| Spec passes locally, fails in Earthly | Earthly cache pointing at an older base image. `earthly --no-cache +<target>` to force rebuild. |
| File ownership assertion wrong | The test image runs entrypoint as root but services as `dp_app` / `nginx` / `vector`. Check which user actually created the file. |
| Env var "not set" but you set it on `docker run -e ...` | `clean_env` strips private vars from the environment at boot. Read via `container-var <NAME>` instead of `$NAME`. |
| Second run of scenario fails, first passes | Leaked state from the first run. Add teardown in `after(:all)` or a sentinel reset in the Earthly target between runs. |
