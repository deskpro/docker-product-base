#!/usr/bin/env bash
#
# Builds PHP, its bundled extensions and the PECL extensions from verified
# source tarballs, laid out like the Debian (sury) packages so the rest of the
# image -- /etc/php/8.3, phpenmod, /usr/bin/php, /usr/sbin/php-fpm8.3 -- does
# not need to know how PHP got there.
#
# Used by the builder-php-source stage of the Dockerfile, one step per RUN so
# the slow steps (PHP, grpc) cache independently:
#
#   build.sh deps       install build dependencies
#   build.sh c-client   build UW-IMAP's c-client (static, for ext/imap)
#   build.sh php        build PHP twice: CLI + shared extensions, then FPM
#   build.sh pecl       build the PECL extensions against the result
#   build.sh collect    stage the runtime files into /out and /out-meta
#
# See docs/explanation/php-source-build.md.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src=/build/src
out=/out
meta=/out-meta

php_series="8.3"
# PHP 8.3's module API number. Debian uses it as the extension directory name
# and the rest of the image assumes that path; checked against php-config below.
php_api="20230831"
ext_dir="/usr/lib/php/${php_api}"
c_client_dir=/opt/c-client
# one job per CPU, but at most one per ~2GB of memory: grpc's C++ gets OOM
# killed at full parallelism on smaller builders
mem_jobs="$(awk '/^MemAvailable:/ { print int($2 / 2097152) }' /proc/meminfo)"
jobs="$(nproc)"
[ "${mem_jobs:-0}" -ge 1 ] && [ "$mem_jobs" -lt "$jobs" ] && jobs="$mem_jobs"

export DEBIAN_FRONTEND=noninteractive

# Debian's own hardening flags (stack protector, fortify, PIE, relro/now, ...),
# so the binaries are built the way the distro packages are. Minus -g: the
# output is stripped anyway, and debug info is most of grpc's memory and time.
set_build_flags() {
  export DEB_BUILD_MAINT_OPTIONS="hardening=+all"
  export DEB_CFLAGS_MAINT_STRIP="-g" DEB_CXXFLAGS_MAINT_STRIP="-g"
  CFLAGS="$(dpkg-buildflags --get CFLAGS)"
  CXXFLAGS="$(dpkg-buildflags --get CXXFLAGS)"
  CPPFLAGS="$(dpkg-buildflags --get CPPFLAGS)"
  LDFLAGS="$(dpkg-buildflags --get LDFLAGS)"
  export CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
  multiarch="$(dpkg-architecture --query DEB_HOST_MULTIARCH)"
}

# fetch <url> <sha256> <dest>
fetch() {
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum --check --strict -
}

cmd_deps() {
  apt-get update
  apt-get install -y --no-install-recommends \
    autoconf \
    bison \
    build-essential \
    ca-certificates \
    curl \
    dpkg-dev \
    file \
    gpg \
    gpg-agent \
    pkg-config \
    quilt \
    re2c \
    xz-utils \
    libargon2-dev \
    libavif-dev \
    libcurl4-openssl-dev \
    libedit-dev \
    libffi-dev \
    libfreetype-dev \
    libicu-dev \
    libjpeg62-turbo-dev \
    libkrb5-dev \
    libldap-dev \
    liblz4-dev \
    libonig-dev \
    libpam0g-dev \
    libpcre2-dev \
    libpng-dev \
    libsasl2-dev \
    libsodium-dev \
    libsqlite3-dev \
    libssl-dev \
    libwebp-dev \
    libxml2-dev \
    libxslt1-dev \
    libzip-dev \
    libzstd-dev \
    zlib1g-dev
  rm -rf /var/lib/apt/lists/*
}

# ext/imap needs UW-IMAP's c-client, which Debian dropped in trixie. Build it
# from the same patched Debian source package sury builds its libc-client from,
# using debian/rules' static target, so imap.so embeds it and the runtime image
# needs no c-client package at all.
cmd_c_client() {
  : "${UW_IMAP_VERSION:?}" "${UW_IMAP_ORIG_SHA256:?}" "${UW_IMAP_DEBIAN_SHA256:?}"
  set_build_flags
  local base="https://packages.sury.org/php/pool/main/u/uw-imap"
  local upstream="${UW_IMAP_VERSION%-*}"
  mkdir -p "$src/uw-imap" && cd "$src"
  fetch "${base}/uw-imap_${upstream}.orig.tar.gz" "$UW_IMAP_ORIG_SHA256" uw-imap.orig.tar.gz
  fetch "${base}/uw-imap_${UW_IMAP_VERSION}.debian.tar.xz" "$UW_IMAP_DEBIAN_SHA256" uw-imap.debian.tar.xz
  tar -xzf uw-imap.orig.tar.gz -C uw-imap --strip-components=1
  tar -xJf uw-imap.debian.tar.xz -C uw-imap
  cd uw-imap
  QUILT_PATCHES=debian/patches quilt push -a -q
  # as debian/rules: Debian's libc is IPv6-safe
  touch ip6
  make ldb \
    EXTRAAUTHENTICATORS=gss \
    EXTRACFLAGS="$CFLAGS $CPPFLAGS -fPIC -D_REENTRANT -DDISABLE_POP_PROXY -Wno-parentheses -Wno-strict-aliasing" \
    EXTRALDFLAGS="$LDFLAGS"
  mkdir -p "${c_client_dir}/include" "${c_client_dir}/lib/${multiarch}"
  cp -L c-client/*.h "${c_client_dir}/include/"
  cp c-client/c-client.a "${c_client_dir}/lib/${multiarch}/libc-client.a"
}

# configure flags shared by both PHP builds. The static/shared split mirrors
# the Debian packages: everything Debian ships as a separate module is built
# shared and enabled through mods-available, the rest is compiled in.
php_common_args() {
  printf '%s\n' \
    --prefix=/usr \
    --program-suffix="${php_series}" \
    --with-libdir="lib/${multiarch}" \
    --localstatedir=/var \
    --disable-rpath \
    --disable-debug \
    --enable-option-checking=fatal \
    --with-pic \
    --without-pear \
    --disable-cgi \
    --disable-phpdbg \
    --with-openssl \
    --with-zlib \
    --with-sodium \
    --with-password-argon2 \
    --with-external-pcre \
    --with-mhash \
    --enable-bcmath=shared \
    --enable-calendar=shared \
    --enable-ctype=shared \
    --with-curl=shared \
    --enable-dom=shared \
    --enable-exif=shared \
    --with-ffi=shared \
    --enable-fileinfo=shared \
    --enable-ftp=shared \
    --enable-gd=shared \
    --with-avif \
    --with-webp \
    --with-jpeg \
    --with-freetype \
    --with-gettext=shared \
    --with-iconv=shared \
    --with-imap=shared,"${c_client_dir}" \
    --with-imap-ssl \
    --with-kerberos \
    --enable-intl=shared \
    --with-ldap=shared \
    --with-ldap-sasl \
    --enable-mbstring=shared \
    --enable-mysqlnd=shared \
    --with-mysql-sock=/var/run/mysqld/mysqld.sock \
    --with-mysqli=shared,mysqlnd \
    --enable-pdo=shared \
    --with-pdo-mysql=shared,mysqlnd \
    --with-pdo-sqlite=shared \
    --enable-phar=shared \
    --enable-posix=shared \
    --with-libedit=shared \
    --enable-shmop=shared \
    --enable-simplexml=shared \
    --enable-soap=shared \
    --enable-sockets=shared \
    --with-sqlite3=shared \
    --enable-sysvmsg=shared \
    --enable-sysvsem=shared \
    --enable-sysvshm=shared \
    --enable-tokenizer=shared \
    --enable-xml=shared \
    --enable-xmlreader=shared \
    --enable-xmlwriter=shared \
    --with-xsl=shared \
    --with-zip=shared
}

# PHP compiles one php.ini path and scan dir into each binary. Debian builds
# every SAPI separately so the CLI reads /etc/php/8.3/cli and FPM reads
# /etc/php/8.3/fpm; we do the same. Build 1 produces the CLI and every shared
# extension; build 2 only links the FPM binary (same flags, so the same static
# core and the extensions from build 1 load into it).
cmd_php() {
  : "${PHP_VERSION:?}" "${PHP_SHA256:?}" "${PHP_GPG_KEY_FINGERPRINTS:?}"
  set_build_flags
  mkdir -p "$src" && cd "$src"

  local tarball="php-${PHP_VERSION}.tar.xz"
  fetch "https://www.php.net/distributions/${tarball}" "$PHP_SHA256" "$tarball"
  curl -fsSL --retry 3 -o "${tarball}.asc" "https://www.php.net/distributions/${tarball}.asc"
  curl -fsSL --retry 3 -o php-keyring.gpg "https://www.php.net/distributions/php-keyring.gpg"
  GNUPGHOME="$(mktemp -d)"
  export GNUPGHOME
  gpg --batch --quiet --import php-keyring.gpg
  # VALIDSIG's last field is the signing key's primary fingerprint, which is
  # what php.net publishes per release series.
  local signer
  signer="$(gpg --batch --status-fd 1 --verify "${tarball}.asc" "$tarball" 2>/dev/null \
    | awk '$2 == "VALIDSIG" { print $NF }')"
  if [ -z "$signer" ] || [[ ":${PHP_GPG_KEY_FINGERPRINTS}:" != *":${signer}:"* ]]; then
    echo "php-${PHP_VERSION}: signature not made by a pinned release manager key (got '${signer}')" >&2
    exit 1
  fi
  echo "php-${PHP_VERSION}: good signature from ${signer}"
  rm -rf "$GNUPGHOME"

  local common
  mapfile -t common < <(php_common_args)

  mkdir php-cli php-fpm
  tar -xJf "$tarball" -C php-cli --strip-components=1
  tar -xJf "$tarball" -C php-fpm --strip-components=1

  (
    cd php-cli
    EXTENSION_DIR="$ext_dir" ./configure "${common[@]}" \
      --with-config-file-path="/etc/php/${php_series}/cli" \
      --with-config-file-scan-dir="/etc/php/${php_series}/cli/conf.d" \
      --enable-pcntl
    make -j"$jobs"
    make install
  )

  (
    cd php-fpm
    EXTENSION_DIR="$ext_dir" ./configure "${common[@]}" \
      --with-config-file-path="/etc/php/${php_series}/fpm" \
      --with-config-file-scan-dir="/etc/php/${php_series}/fpm/conf.d" \
      --sysconfdir="/etc/php/${php_series}/fpm" \
      --disable-cli \
      --enable-fpm
    make -j"$jobs" sapi/fpm/php-fpm
    install -m 0755 sapi/fpm/php-fpm "/usr/sbin/php-fpm${php_series}"
  )

  [ "$(php-config${php_series} --extension-dir)" = "$ext_dir" ] \
    || { echo "unexpected extension dir: $(php-config${php_series} --extension-dir)" >&2; exit 1; }
  "php${php_series}" -v
  "php-fpm${php_series}" -v
}

# extra ./configure flags per PECL extension
pecl_configure_args() {
  case "$1" in
    # as sury's php-redis: igbinary serializer, lzf (bundled), zstd and lz4 (system)
    redis) printf '%s\n' --enable-redis-igbinary --enable-redis-lzf \
      --enable-redis-zstd --with-libzstd --enable-redis-lz4 --with-liblz4 ;;
  esac
}

# PECL_EXTENSIONS is a space-separated list of <name>-<version>:<sha256>, built
# in order (igbinary must come before redis).
cmd_pecl() {
  : "${PECL_EXTENSIONS:?}"
  set_build_flags
  mkdir -p "$src/pecl" && cd "$src/pecl"
  local spec pkg sum name args
  for spec in $PECL_EXTENSIONS; do
    pkg="${spec%%:*}"
    sum="${spec#*:}"
    name="${pkg%-*}"
    fetch "https://pecl.php.net/get/${pkg}.tgz" "$sum" "${pkg}.tgz"
    tar -xzf "${pkg}.tgz"
    mapfile -t args < <(pecl_configure_args "$name")
    (
      cd "$pkg"
      "phpize${php_series}"
      ./configure --with-php-config="php-config${php_series}" "${args[@]}"
      make -j"$jobs"
      make install
    )
  done
}

# lib_package <path> -- the Debian package owning a shared library. With the
# /usr merge a library can be registered under /lib or /usr/lib, so try both.
lib_package() {
  local p candidates=("$1" "$(realpath "$1")")
  case "$1" in
    /lib/*) candidates+=("/usr$1") ;;
    /usr/lib/*) candidates+=("${1#/usr}") ;;
  esac
  for p in "${candidates[@]}"; do
    dpkg-query --search "$p" 2>/dev/null | head -n1 | cut -d: -f1 && return 0
  done
  echo "no package owns $1" >&2
  return 1
}

cmd_collect() {
  mkdir -p "$out/usr/bin" "$out/usr/sbin" "$out$ext_dir" "$meta"

  cp -a "/usr/bin/php${php_series}" "/usr/bin/phar${php_series}.phar" "/usr/bin/phar${php_series}" "$out/usr/bin/"
  cp -a "/usr/sbin/php-fpm${php_series}" "$out/usr/sbin/"
  cp -a "$ext_dir"/*.so "$out$ext_dir/"
  find "$out" -type f \( -name '*.so' -o -perm -u+x \) -exec sh -c \
    'file -b "$1" | grep -q ELF && strip --strip-unneeded "$1"' _ {} \;

  # the module table must describe exactly what was built
  local listed built
  listed="$(awk '!/^#/ && NF { print $1 }' "$here/modules.txt" | sort)"
  built="$(cd "$out$ext_dir" && ls -1 *.so | sed 's/\.so$//' | sort)"
  if [ "$listed" != "$built" ]; then
    echo "modules.txt does not match the built extensions:" >&2
    diff <(echo "$listed") <(echo "$built") >&2 || true
    exit 1
  fi

  # runtime packages: whatever owns the shared libraries the binaries and
  # extensions link against, resolved here against the same Debian release
  local ldd_out libs lib
  ldd_out="$(find "$out" -type f \( -name '*.so' -o -perm -u+x \) -exec sh -c \
    'file -b "$1" | grep -q ELF && ldd "$1"' _ {} \;)"
  if grep -q 'not found' <<<"$ldd_out"; then
    echo "unresolved shared libraries:" >&2
    grep 'not found' <<<"$ldd_out" >&2
    exit 1
  fi
  libs="$(awk '$2 == "=>" && $3 ~ /^\// { print $3 }' <<<"$ldd_out" | sort -u)"
  for lib in $libs; do
    lib_package "$lib" || exit 1
  done | sort -u > "$meta/runtime-packages.txt"

  cp "$here/modules.txt" "$here/install-runtime.sh" "$meta/"
  echo "runtime packages:"
  sed 's/^/  /' "$meta/runtime-packages.txt"
}

case "${1:-}" in
  deps) cmd_deps ;;
  c-client) cmd_c_client ;;
  php) cmd_php ;;
  pecl) cmd_pecl ;;
  collect) cmd_collect ;;
  *) echo "usage: $0 {deps|c-client|php|pecl|collect}" >&2; exit 2 ;;
esac
