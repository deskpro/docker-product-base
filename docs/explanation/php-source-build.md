---
title: Building PHP from source
type: explanation
last_reviewed: 2026-10-22
status: experimental
---

# Building PHP from source

By default the image installs PHP 8.3 from [deb.sury.org](https://packages.sury.org/php/). Setting the `PHP_INSTALL_METHOD=source` build arg compiles it from the php.net release tarball instead. This lets the image pick up a PHP security release on the day it ships rather than when the packages are rebuilt. For example, 8.3.36 was released on 2026-10-21, but sury was still shipping 8.3.35.

The source path is **experimental**. It exists so the two builds can be compared, and it is not what CI or Docker Hub builds.

```sh
# build it
docker build --build-arg PHP_INSTALL_METHOD=source -t deskpro/docker-product-base:php-source .

# run the full test suite against it
earthly -P ./test+test --PHP_INSTALL_METHOD=source

# diff its PHP against the default build
docker build -t deskpro/docker-product-base:php-deb .
test/compare-php-builds.sh deskpro/docker-product-base:php-deb deskpro/docker-product-base:php-source
```

## Design: same layout, different origin

Nothing outside the PHP stages knows which method was used. The rest of the image, the product image on top, and operators' `/deskpro/config/php.d` overrides all rely on the Debian layout, so the source build reproduces it:

| Debian package layout | How the source build matches it |
| --- | --- |
| `/usr/bin/php` → alternatives → `/usr/bin/php8.3`, `/usr/sbin/php-fpm8.3` | `--program-suffix=8.3`, `update-alternatives` as `php8.3-cli` does |
| CLI reads `/etc/php/8.3/cli/php.ini` + `cli/conf.d`; FPM reads `fpm/php.ini` + `fpm/conf.d` | PHP compiles a single ini path into each binary, so it is built twice, as Debian does. The CLI build produces the CLI and every shared extension. The FPM build uses the same flags and links only `php-fpm`. |
| Extensions in `/usr/lib/php/20230831` | `EXTENSION_DIR` at configure time |
| Optional extensions are shared and enabled via `mods-available/*.ini` + `phpenmod` | The same static/shared split. [`php-source/modules.txt`](../../php-source/modules.txt) records each module's Debian priority, so `conf.d/NN-*.ini` load order is unchanged. `phpenmod` comes from Debian's own `php-common`, which contains only the helper scripts. |
| `pcntl` in the CLI only | `--enable-pcntl` only in the CLI build |
| Hardened build flags | `dpkg-buildflags` with `hardening=+all` |
| sury's `opcache.ini` sets `opcache.jit=off` | Written into the generated `opcache.ini` too. Without it, setting `PHP_OPCACHE_JIT_BUFFER_SIZE` would turn the tracing JIT on here but not on the deb build. |
| MySQL default socket `/var/run/mysqld/mysqld.sock` | `--with-mysql-sock` |
| `session.save_path` patched to `/var/lib/php/sessions` | Set explicitly in the repo's `php.ini` files. This makes no difference on the deb build. |

The Dockerfile selects between `stage1-php-deb` and `stage1-php-source` with `FROM stage1-php-${PHP_INSTALL_METHOD}`. BuildKit only builds the stages the selected method needs, so the default build never compiles anything new.

## What gets built, and how it's verified

[`php-source/build.sh`](../../php-source/build.sh) runs in the `builder-php-source` stage. Each step is a separate `RUN`, so the slow ones cache independently:

1. **c-client**: `ext/imap` needs UW-IMAP's c-client, which Debian dropped in trixie. It is built from the same patched Debian source package that sury builds `libc-client2007e` from, using `debian/rules`' static target, and linked into `imap.so`. The runtime image needs no c-client package.
2. **PHP**: the tarball is pinned by sha256. Its `.asc` must also verify against a primary key fingerprint in `PHP_GPG_KEY_FINGERPRINTS`. Those are the PHP 8.3 release managers listed at <https://www.php.net/gpg-keys.php>.
3. **PECL** (`igbinary`, `redis`, `protobuf`, `opentelemetry`, `grpc`): pinned by sha256 only, because PECL publishes no signatures. The versions match what the deb path ships today. `redis` is built with the same serializers and compressors as sury's (igbinary; lzf, zstd, lz4).
4. **collect**: stages the binaries and `.so` files, then fails if they don't match `modules.txt` exactly. It derives the runtime package list from `ldd`, so the runtime stage installs only the libraries PHP actually links against.

[`php-source/install-runtime.sh`](../../php-source/install-runtime.sh) then runs in `stage1-php-source`. It installs those libraries, writes the `mods-available` files, runs `phpenmod`, and registers the alternatives.

`/usr/local/share/deskpro/php-install-method` (`deb` or `source`) and the `org.deskpro.php-install-method` label record which method was used. The `always/deps_spec.rb` invariants use the marker file. In a source build, they also assert that no `php8.3-*` package is installed.

## Known differences from the deb build

These differences are deliberate, or inherent to building from upstream source:

- **gd is PHP's bundled copy** rather than the system `libgd3`. Upstream recommends it, and it takes `libgd3`, `libheif`, `libtiff` and `libxpm` (and their CVEs) out of PHP's dependencies. XPM support is not built.
- **Timezone data is PHP's bundled timezonedb.** Debian patches PHP to read the system tzdata (`timezone_version_get()` returns `0.system`).
- **No Debian/sury patches to PHP itself.** Debian carries a small set of mostly packaging patches. The upstream behaviour applies instead.
- **No `php8.3-*` packages are registered with dpkg.** A downstream `apt-get install php8.3-<anything>` would pull in sury's `php8.3-common` and overwrite these files. Extra extensions have to be compiled in `builder-php-source` instead. The image ships no `phpize8.3`, just as the deb path ships no `php8.3-dev`.

- **`igbinary APCu serializer ABI` reports `no`.** sury builds igbinary against APCu's headers, but neither image ships APCu, so this has no effect.

`test/compare-php-builds.sh` reports every other difference, such as library versions and ini defaults. It masks the PHP version, so a version bump on one side doesn't fill the diff.

## Cost

- **Image size**: the same to within about 0.1%. Measured on arm64, the source image was 1,645 MB against 1,644 MB for the deb image. Nothing from `builder-php-source` ships except the stripped binaries and `.so` files. The runtime libraries come from the `ldd` scan, so no `-dev` packages or recommends are installed.
- **Build time**: on a cold cache, roughly 6 minutes for PHP and 9 for the PECL step on a 16-CPU / 8 GB builder. Most of the PECL time is grpc's C++. Parallelism is capped at one job per ~2 GB of available memory, because grpc gets OOM-killed at full parallelism on 8 GB. Each step is its own cached layer, but any edit under `php-source/` invalidates them all.
