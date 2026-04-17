---
title: Add a new test
type: how-to
last_reviewed: 2026-04-17
status: current
---

# Add a new test

Which shape of test to use depends on what you're asserting:

| Kind | Use when | Where it goes |
| --- | --- | --- |
| Always-true invariant | Something must hold in every configuration (user exists, package installed, critical path present). | `serverspec/spec/always/` |
| Default-web behaviour | A claim about the plain `web` run mode with no customisation. | `serverspec/spec/default_web/` |
| Single-feature case | One self-contained behaviour, usually tied to a specific story. | `serverspec/spec/cases/simple/sc-<id>-<name>_spec.rb` |
| Multi-step scenario | You need specific mounts, env vars, or a container restart between assertions. | `serverspec/spec/scenarios/<name>/` + a new Earthly target |

For anything in the first three rows, no Earthfile change is needed — the existing targets pick up new files in those directories automatically. Scenarios need a new target.

## Adding a simple spec

Pick one of the spec directories above and drop in a new file. Pattern:

```ruby
# test/serverspec/spec/cases/simple/sc-99999-my-feature_spec.rb
require 'spec_helper'

describe "Case SC-99999: My feature" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  after(:all) do
    ENV.delete('MY_FEATURE_VAR')
  end

  it "feature does the thing when enabled" do
    ENV['MY_FEATURE_VAR'] = 'true'
    output = `eval-tpl -f /path/to/template.tmpl`
    expect(output).to include("expected substring")
  end
end
```

Run it:

```bash
earthly -P +test-serverspec-simple-cases     # or -serverspec-web, depending on directory
```

## Adding a scenario

Use this shape when you need:

- A specific mount to be in place before the container boots.
- An env var set that would affect other specs if applied globally.
- A container restart between assertions (i.e. you want to test idempotence).

### 1. Lay out the scenario's files

```
test/serverspec/spec/scenarios/my-thing/
├── 01_applied_spec.rb              # first-run assertions
├── 02_persisted_spec.rb            # after-restart assertions (if needed)
└── deskpro_dir/                    # optional fixture mounted at /deskpro
    └── config/
        └── php.d/
            └── 99-my-thing.ini
```

### 2. Write the specs

Use numeric prefixes only if order matters — they're picked up in lexicographic order by RSpec.

```ruby
# spec/scenarios/my-thing/01_applied_spec.rb
require 'spec_helper'

describe "my-thing is applied at boot" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/etc/php/8.3/fpm/conf.d/99-my-thing.ini') do
    it { should exist }
  end
end
```

### 3. Add the Earthly target

Copy the shape of an existing target in [`Earthfile`](../../Earthfile) that's closest to what you need. For a scenario with a mounted directory and two runs separated by a restart:

```earthly
test-my-thing:
    FROM earthly/dind:alpine
    COPY --dir serverspec/spec/scenarios/my-thing/deskpro_dir /tmp/deskpro-dir
    WITH DOCKER --load deskpro/docker-product-base:test=+base-image
        RUN \
            docker run -d --name test \
                -v /tmp/deskpro-dir:/deskpro \
                deskpro/docker-product-base:test web \
            && docker exec test /bin/sh -c 'cd /test/serverspec && rspec spec/scenarios/my-thing/01_applied_spec.rb' \
            && docker stop test \
            && docker start test \
            && docker exec test /bin/sh -c 'cd /test/serverspec && rspec spec/scenarios/my-thing/02_persisted_spec.rb'
    END
```

### 4. Wire it into `+test`

In the `+test` block, add your target to the appropriate `WAIT` section:

```earthly
test:
    BUILD +base-image
    WAIT
        BUILD +test-serverspec-web
        BUILD +test-serverspec-opc
        BUILD +test-serverspec-simple-cases
        BUILD +test-custom-configs
        BUILD +test-custom-logs-group
        BUILD +test-my-thing                  # <-- here
    END
    ...
```

Put it in the first `WAIT` block unless it has an ordering dependency on something else.

### 5. Run it

```bash
earthly -P +test-my-thing
```

Iterate until it passes. Then run the full suite once:

```bash
earthly -P +test
```

## Conventions to follow

- **Always wait for readiness.** Every `before(:all)` block starts with `system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise`. Without it, your spec races the container's boot and will flake.
- **Clean up.** The container is reused across examples in a scenario. Remove env vars, temp files, and custom configs in `after(:all)` / `after(:each)` so the next spec sees a clean slate.
- **Prefer Serverspec matchers over raw commands.** `describe file(...)` and `describe port(...)` produce clearer failure messages than parsing `system()` output.
- **Fixtures live with the scenario.** Don't put them in some shared location — the scenario directory is self-contained by design.
- **Don't modify `spec/always/`** to make a new test pass. Those are the image's non-negotiables; if one fails, the image is broken.
