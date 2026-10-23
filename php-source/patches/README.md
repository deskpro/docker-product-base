# PHP source patches

Applied in order to both PHP builds by `build.sh php`. Each one is a verbatim
copy of a patch from the Debian packaging, so the source build behaves like
the deb build where it matters.

| Patch | Why |
| --- | --- |
| `0007-Add-support-for-use-of-the-system-timezone-database.patch` | Adds `--with-system-tzdata`, so PHP reads `/usr/share/zoneinfo` (kept current by the `tzdata` package) instead of its bundled timezone DB. PHP 8.3 is security-only, so its bundled DB no longer gets IANA updates. |
| `0021-Use-system-timezone.patch` | Its companion: guess the default timezone from the system when `date.timezone` is unset, as the deb build does. |

Source: sury's `php8.3` source package `8.3.36-1+0~20261021.88+debian13~1.gbp250f7c`,
`php8.3_8.3.36-1+0~20261021.88+debian13~1.gbp250f7c.debian.tar.xz`
(sha256 `d29d98b25010ab7efc5f125bddc475401d336b1702471f2f3d35a80d3c2e948d`),
`debian/patches/`. Its `orig.tar.xz` is byte-identical to php.net's release
tarball. The patches are vendored rather than downloaded because sury's pool
drops old source packages when they rebuild.

When bumping `PHP_VERSION`, check the patches still apply (the build fails if
they don't) and refresh them from the matching sury source package.
