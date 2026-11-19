# Optional: build PHP from the php.net source tarball instead of installing it
# from the SURY apt repo. This is a BUILD arg (not a runtime env var, so it is
# intentionally not listed in container-var-reference.json).
#   PHP_SOURCE_VERSION=""        (default) PHP 8.3.x comes from SURY apt, exactly as before.
#   PHP_SOURCE_VERSION="8.3.37"  PHP is compiled from php-8.3.37.tar.gz (GPG-verified,
#                                see builder-php-src) with the same SAPIs (cli, fpm)
#                                and extension set; grpc/opentelemetry/protobuf/redis
#                                are rebuilt against that PHP rather than reusing the
#                                SURY-built .so files. Debian/SURY filesystem layout
#                                (/etc/php/8.3/*, /usr/lib/php/20230831, php-fpm8.3,
#                                phpenmod/phpdismod) is reproduced so nothing downstream changes.
# Only a PHP 8.3.x version may be given (the extension API 20230831 and the
# /etc/php/8.3 paths used throughout this image are 8.3-specific).
ARG PHP_SOURCE_VERSION=""

# builder stage -- builds PHP packages
# outputs: /usr/lib/php/20230831/protobuf.so
# outputs: /usr/lib/php/20230831/opentelemetry.so
FROM debian:13.7-slim AS builder-php-exts
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates apt-transport-https curl lsb-release build-essential \
    && curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
    && sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list' \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-install-suggests -y \
    make \
    php8.3-cli \
    php8.3-dev \
    php8.3-common \
    php8.3-xml \
    php8.3-grpc \
    php-pear \
    && pecl install opentelemetry protobuf \
    && rm -rf /var/lib/apt/lists/*

# builder stage -- OPTIONAL: compiles PHP 8.3 (cli + fpm) and the non-bundled
# extensions (redis, grpc, opentelemetry, protobuf) from source.
# Does nothing unless PHP_SOURCE_VERSION is set: when empty every step below is
# skipped and /out is left empty, so the COPY in stage2 is a no-op and PHP keeps
# coming from SURY apt (see stage1).
# Mirrors the Debian/SURY layout so the rest of the image is unchanged:
#   /usr/bin/php8.3 (+ php), /usr/sbin/php-fpm8.3, /usr/lib/php/20230831/*.so,
#   /etc/php/8.3/{cli,fpm}/conf.d, /etc/php/8.3/mods-available, phpenmod/phpdismod.
# outputs: /out/ (everything above) and /out/php-src-runtime-deps (apt packages the
#          result links against; installed in stage2)
FROM debian:13.7-slim AS builder-php-src
ARG PHP_SOURCE_VERSION
# php.net release signing keys for PHP 8.3 (https://www.php.net/gpg-keys.php#gpg-8.3)
#   1198C0117593497A5EC5C199286AF1F9897469DC  Pierrick Charron
#   AFD8691FDAEDF03BDF6E460563F15A9B715376CA  Eric Mann
#   C28D937575603EB4ABB725861C0779DC5C0A9DE4  Jakub Zelenka
ARG PHP_GPG_KEY_FINGERPRINTS="1198C0117593497A5EC5C199286AF1F9897469DC:AFD8691FDAEDF03BDF6E460563F15A9B715376CA:C28D937575603EB4ABB725861C0779DC5C0A9DE4"
# PECL extensions: PECL publishes no signatures, so pin version + sha256 of the tarball
ARG PECL_REDIS_VERSION="6.3.0"
ARG PECL_REDIS_SHA256="0d5141f634bd1db6c1ddcda053d25ecf2c4fc1c395430d534fd3f8d51dd7f0b5"
ARG PECL_GRPC_VERSION="1.84.0"
ARG PECL_GRPC_SHA256="555716233a5cc9a6baa605719f87b7688a88fb8bfdd9b4493396276244d56625"
ARG PECL_OPENTELEMETRY_VERSION="1.4.2"
ARG PECL_OPENTELEMETRY_SHA256="a355329259f373c5c7327e66310481726cfabac50cb5483eba000bec791d5017"
ARG PECL_PROTOBUF_VERSION="5.36.2"
ARG PECL_PROTOBUF_SHA256="f0a17c67de29df0fb0e5215a381df9b155125e1ace6252dd617bf16b4194dd5b"

RUN [ -z "$PHP_SOURCE_VERSION" ] || { \
    case "$PHP_SOURCE_VERSION" in \
    8.3.*) ;; \
    *) echo "PHP_SOURCE_VERSION must be an 8.3.x release (got '$PHP_SOURCE_VERSION')" >&2; exit 1 ;; \
    esac \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl gnupg dirmngr \
    # Debian does not ship the c-client library the imap extension needs, so (as in the
    # runtime image) take libc-client2007e-dev from SURY, pinned low so it is the only thing used from it
    && curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
    && . /etc/os-release \
    && echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/php.list \
    && printf 'Package: *\nPin: origin packages.sury.org\nPin-Priority: 100\n' > /etc/apt/preferences.d/98sury \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential autoconf pkg-config re2c bison file libc-client2007e-dev \
    libxml2-dev libssl-dev libsqlite3-dev libcurl4-openssl-dev libonig-dev \
    libzip-dev zlib1g-dev libgd-dev libkrb5-dev libldap-dev libsasl2-dev \
    libicu-dev libargon2-dev libsodium-dev libxslt1-dev libreadline-dev libffi-dev \
    && rm -rf /var/lib/apt/lists/*; \
    }

# download php.net tarball and verify it against the pinned release keys
RUN mkdir -p /out && { [ -z "$PHP_SOURCE_VERSION" ] || { \
    mkdir -p /usr/src/php-dl && cd /usr/src/php-dl \
    && curl -fsSLo php.tar.gz "https://www.php.net/distributions/php-${PHP_SOURCE_VERSION}.tar.gz" \
    && curl -fsSLo php.tar.gz.asc "https://www.php.net/distributions/php-${PHP_SOURCE_VERSION}.tar.gz.asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && for fp in $(echo "$PHP_GPG_KEY_FINGERPRINTS" | tr ':' ' '); do \
    for server in hkps://keyserver.ubuntu.com hkps://keys.openpgp.org; do \
    gpg --batch --keyserver "$server" --recv-keys "$fp" && break; \
    done; \
    done \
    # verify the keys we imported are exactly the pinned ones
    && key_fingerprints="$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "pub" { want = 1 } $1 == "fpr" && want { print $10; want = 0 }' | sort | paste -s -d:)" \
    && pinned_fingerprints="$(echo "$PHP_GPG_KEY_FINGERPRINTS" | tr ':' '\n' | sort | paste -s -d:)" \
    && { [ "$pinned_fingerprints" = "$key_fingerprints" ] || { \
    echo "php.net key fingerprints do not match"; \
    exit 1; \
    }; } \
    && gpg --batch --verify php.tar.gz.asc php.tar.gz \
    && rm -rf "$GNUPGHOME"; \
    }; }

# compile PHP twice (cli, fpm) with Debian-style paths, so each SAPI reads
# /etc/php/8.3/<sapi>/php.ini and /etc/php/8.3/<sapi>/conf.d. Bundled extensions
# are compiled in, except opcache and phar which stay loadable (like the Debian
# packages): opcache is enabled via mods-available, phar is enabled by default
# and disabled again by `phpdismod phar` in stage2, same as with SURY.
RUN [ -z "$PHP_SOURCE_VERSION" ] || { \
    php_flags="--prefix=/usr --libdir=/usr/lib/php --mandir=/usr/share/man --localstatedir=/var \
    --without-pear --disable-cgi --disable-phpdbg \
    --enable-bcmath --enable-calendar --enable-ctype --enable-dom --enable-exif --enable-fileinfo \
    --enable-ftp --enable-gd --with-external-gd --with-imap --with-imap-ssl --with-kerberos --enable-intl --enable-mbstring --enable-mysqlnd \
    --enable-opcache=shared --enable-pcntl --enable-phar=shared --enable-posix --enable-shmop \
    --enable-simplexml --enable-soap --enable-sockets --enable-sysvmsg --enable-sysvsem \
    --enable-sysvshm --enable-tokenizer --enable-xml --enable-xmlreader --enable-xmlwriter \
    --with-curl --with-ffi --with-gettext --with-iconv --with-ldap=/usr --with-ldap-sasl \
    --with-mysqli=mysqlnd --with-openssl --with-password-argon2 --with-pdo-mysql=mysqlnd \
    --with-pdo-sqlite --with-readline --with-sodium --with-sqlite3 --with-xsl --with-zip --with-zlib" \
    && cd /usr/src \
    && mkdir php-cli php-fpm \
    && tar -xzf php-dl/php.tar.gz -C php-cli --strip-components=1 \
    && tar -xzf php-dl/php.tar.gz -C php-fpm --strip-components=1 \
    && cd /usr/src/php-cli \
    && EXTENSION_DIR=/usr/lib/php/20230831 ./configure $php_flags \
    --with-config-file-path=/etc/php/8.3/cli --with-config-file-scan-dir=/etc/php/8.3/cli/conf.d \
    --enable-cli --disable-fpm \
    && make -j"$(nproc)" \
    && make install \
    && cd /usr/src/php-fpm \
    && EXTENSION_DIR=/usr/lib/php/20230831 ./configure $php_flags \
    --sysconfdir=/etc/php/8.3/fpm --with-config-file-path=/etc/php/8.3/fpm --with-config-file-scan-dir=/etc/php/8.3/fpm/conf.d \
    --disable-cli --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data \
    && make -j"$(nproc)" \
    && install -m 0755 sapi/fpm/php-fpm /usr/sbin/php-fpm8.3 \
    && cd / && rm -rf /usr/src/php-cli /usr/src/php-fpm; \
    }

# PECL extensions, built against the PHP above (phpize/php-config from the install)
RUN [ -z "$PHP_SOURCE_VERSION" ] || { \
    cd /usr/src \
    && for spec in "redis:${PECL_REDIS_VERSION}:${PECL_REDIS_SHA256}" \
    "grpc:${PECL_GRPC_VERSION}:${PECL_GRPC_SHA256}" \
    "opentelemetry:${PECL_OPENTELEMETRY_VERSION}:${PECL_OPENTELEMETRY_SHA256}" \
    "protobuf:${PECL_PROTOBUF_VERSION}:${PECL_PROTOBUF_SHA256}"; do \
    name="${spec%%:*}"; rest="${spec#*:}"; version="${rest%%:*}"; sha256="${rest#*:}"; \
    curl -fsSLo "${name}.tgz" "https://pecl.php.net/get/${name}-${version}.tgz" \
    && echo "${sha256}  ${name}.tgz" | sha256sum -c - \
    && mkdir "pecl-${name}" && tar -xzf "${name}.tgz" -C "pecl-${name}" --strip-components=1 \
    && ( cd "pecl-${name}" && phpize && ./configure --enable-"${name}" && make -j"$(nproc)" && make install ) \
    || exit 1; \
    done \
    && rm -rf /usr/src/pecl-* /usr/src/*.tgz; \
    }

# assemble /out in the Debian/SURY layout
RUN [ -z "$PHP_SOURCE_VERSION" ] || { \
    mkdir -p /out/usr/bin /out/usr/sbin /out/usr/lib/php \
    /out/etc/php/8.3/mods-available /out/etc/php/8.3/cli/conf.d /out/etc/php/8.3/fpm/conf.d /out/etc/php/8.3/fpm/pool.d \
    && cp /usr/bin/php /out/usr/bin/php8.3 \
    && ln -s php8.3 /out/usr/bin/php \
    && cp /usr/sbin/php-fpm8.3 /out/usr/sbin/php-fpm8.3 \
    && cp -a /usr/lib/php/20230831 /out/usr/lib/php/20230831 \
    && find /out -type f \( -name '*.so' -o -path '*/usr/bin/*' -o -path '*/usr/sbin/*' \) -exec strip --strip-unneeded {} + \
    # minimal stand-in for Debian's phpenmod/phpdismod (same mods-available/<prio>-<name>.ini symlink scheme)
    && printf '%s\n' \
    '#!/bin/sh' \
    'etc="${PHP_ETC:-/etc/php/8.3}"' \
    'act="${0##*/}"' \
    'for m in "$@"; do' \
    '  case "$m" in -*) continue ;; esac' \
    '  ini="$etc/mods-available/$m.ini"' \
    '  [ -f "$ini" ] || { echo "WARNING: module $m ini file does not exist" >&2; continue; }' \
    '  prio="$(sed -n "s/^; *priority=\([0-9][0-9]*\).*/\1/p" "$ini" | head -n 1)"' \
    '  for sapi in cli fpm; do' \
    '    link="$etc/$sapi/conf.d/${prio:-20}-$m.ini"' \
    '    if [ "$act" = phpenmod ]; then ln -sf "../../mods-available/$m.ini" "$link"; else rm -f "$link"; fi' \
    '  done' \
    'done' > /out/usr/sbin/phpenmod \
    && chmod 0755 /out/usr/sbin/phpenmod \
    && ln -s phpenmod /out/usr/sbin/phpdismod \
    # default-enabled modules (the rest are compiled in)
    && printf '; priority=10\nzend_extension=opcache.so\n' > /out/etc/php/8.3/mods-available/opcache.ini \
    && printf '; priority=20\nextension=phar.so\n' > /out/etc/php/8.3/mods-available/phar.ini \
    && printf '; priority=20\nextension=redis.so\n' > /out/etc/php/8.3/mods-available/redis.ini \
    && PHP_ETC=/out/etc/php/8.3 /out/usr/sbin/phpenmod opcache phar redis \
    # smoke test the result before it leaves the builder
    && /out/usr/bin/php8.3 -n -v \
    && /out/usr/sbin/php-fpm8.3 -n -v \
    # record which apt packages the binaries and extensions link against
    && ( find /out -type f \( -name '*.so' -o -path '*/usr/bin/*' -o -path '*/usr/sbin/*' \) -exec ldd {} + 2>/dev/null \
    | tee /tmp/ldd.out | awk '/=> \// { print $3 }' | sort -u | xargs -r realpath \
    | xargs -r dpkg-query -S | sed 's/:.*//' | sort -u > /out/php-src-runtime-deps ) \
    && ! grep 'not found' /tmp/ldd.out \
    && [ -s /out/php-src-runtime-deps ]; \
    }

# Use pre-built gomplate v5.3.1 binary
FROM debian:13.7-slim AS builder-go-binaries
ARG GOMPLATE_VERSION="5.3.1"
ARG TARGETARCH
ARG TARGETVARIANT
RUN apt-get update && apt-get install -y curl ca-certificates \
    && case "$TARGETARCH" in \
        amd64|arm64|386|ppc64le|s390x) GOMPLATE_ARCH="$TARGETARCH" ;; \
        arm) \
            case "$TARGETVARIANT" in \
                v7) GOMPLATE_ARCH="armv7" ;; \
                v6) GOMPLATE_ARCH="armv6" ;; \
                *) echo "Unsupported ARM variant for gomplate: ${TARGETVARIANT:-<empty>}" >&2; exit 1 ;; \
            esac ;; \
        *) echo "Unsupported TARGETARCH for gomplate: ${TARGETARCH:-<empty>}" >&2; exit 1 ;; \
    esac \
    && echo "Downloading gomplate v${GOMPLATE_VERSION} for platform: ${TARGETARCH}${TARGETVARIANT:+/${TARGETVARIANT}} (asset: ${GOMPLATE_ARCH})" \
    && curl -fsSL "https://github.com/hairyhenderson/gomplate/releases/download/v${GOMPLATE_VERSION}/gomplate_linux-${GOMPLATE_ARCH}" -o /usr/local/bin/gomplate \
    && chmod +x /usr/local/bin/gomplate \
    && /usr/local/bin/gomplate --version



# Builds the smokescreen egress forward proxy from source.
# Stripe does not publish binary releases or an official image for
# smokescreen, so instead of a downloaded+checksummed binary (the pattern
# used for gomplate below) we pin an exact upstream commit via Go module
# pseudo-version + go.sum and let `go mod download` verify it against both
# go.sum and the public sum.golang.org checksum database.
#   Pinned commit: 82f05bfded5885914108d3f6eb9bf91ebd871728 (v0.0.5-0.20260909080646-82f05bfded58)
#   Verified: GPG-signed by GitHub on the upstream commit (gauthamw-stripe, 2026-09-09)
#   Checksum: see smokescreen/go.sum -- "github.com/stripe/smokescreen v0.0.5-..." h1: line
FROM docker.io/library/golang:1.26.10 AS builder-smokescreen
WORKDIR /src
COPY smokescreen/go.mod smokescreen/go.sum ./
RUN go mod download
COPY smokescreen/main.go ./
RUN CGO_ENABLED=0 go build -trimpath -o /out/smokescreen . \
    && /out/smokescreen --help

# builder stage -- builds essential security-patched packages from source
# SIMPLIFIED: Use system packages from debian:13.7-slim instead of source builds
FROM debian:13.7-slim AS builder-security-packages
ARG USE_SYSTEM_PACKAGES_ONLY=true

# If using system packages only, just install the latest available packages
RUN if [ "$USE_SYSTEM_PACKAGES_ONLY" = "true" ]; then \
    echo "Using debian:13.7-slim system packages instead of source builds" \
    && apt-get update \
    && apt-get install -y \
    sqlite3 libsqlite3-0 \
    libexpat1 libexpat1-dev \
    libaom3 libaom-dev \
    zlib1g zlib1g-dev \
    libtiff6 libtiff-dev \
    libwebp7 libwebp-dev \
    libopenjp2-7 libopenjp2-7-dev \
    curl libcurl4 libcurl4-openssl-dev \
    rsync \
    && rm -rf /var/lib/apt/lists/* \
    && echo "All packages installed from system repositories"; \
    fi

# Create symlinks in /usr/local for compatibility
RUN mkdir -p /usr/local/bin /usr/local/lib \
    && ln -sf /usr/bin/sqlite3 /usr/local/bin/sqlite3 \
    && ln -sf /usr/bin/curl /usr/local/bin/curl \
    && ln -sf /usr/bin/rsync /usr/local/bin/rsync \
    && echo "System package setup complete"
# stage1 -- debian with security patches first, then packages
FROM debian:13.7-slim AS stage1
ARG BASE_IMAGE_COMMIT="unknown"
LABEL org.deskpro.base-image-commit="$BASE_IMAGE_COMMIT"
ENV TZ=UTC
WORKDIR /srv/deskpro
USER root

# Copy security-patched packages from builder (system packages with symlinks)
# When using USE_SYSTEM_PACKAGES_ONLY=true, these are just symlinks to system packages
COPY --from=builder-security-packages /usr/local/bin/ /usr/local/bin/
COPY --from=builder-security-packages /usr/local/lib/ /usr/local/lib/
# No header files needed for simplified system package approach
RUN echo "System packages with symlinks copied successfully"

# Configure dynamic linker and install system packages (simplified approach)
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/usr-local.conf \
    && ldconfig \
    # Install system packages - debian:13.7-slim has latest security updates
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y \
    ca-certificates \
    apt-transport-https \
    gnupg \
    lsb-release \
    sudo \
    vim \
    less \
    procps \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && echo "Core system packages installed"

# Install PHP and essential packages (simplified for system packages approach)
RUN mkdir -p /etc/systemd/system \
    && echo '#!/bin/bash' > /usr/bin/systemctl && chmod +x /usr/bin/systemctl \
    && echo '#!/bin/bash' > /usr/sbin/invoke-rc.d && chmod +x /usr/sbin/invoke-rc.d \
    # Redirect logger to /dev/null to prevent socket errors during build
    && mkdir -p /dev \
    && echo '#!/bin/bash' > /usr/bin/logger && echo 'exit 0' >> /usr/bin/logger && chmod +x /usr/bin/logger \
    # Install essential packages without complex repository setup
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    bc \
    default-mysql-client \
    git \
    libfcgi-bin \
    libldap-common \
    nano \
    vim-tiny \
    openssl \
    poppler-utils \
    ripgrep \
    sudo \
    supervisor \
    tzdata \
    cpanminus \
    libpcre2-8-0 \
    libssl3t64 \
    zlib1g \
    # Clean up
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    # Create vim symlink
    && ln -sf /usr/bin/vim.tiny /usr/bin/vim \
    # Restore real logger for runtime and create /dev/log
    && rm -f /usr/bin/logger \
    && apt-get update && apt-get install -y --no-install-recommends bsdutils && rm -rf /var/lib/apt/lists/* \
    && touch /dev/log && chmod 666 /dev/log

# Install PHP packages in separate step to isolate any issues
ARG PHP_SOURCE_VERSION
RUN export DEBIAN_FRONTEND=noninteractive \
    # Add PHP repository for latest versions
    && apt-get update \
    && apt-get install -y ca-certificates apt-transport-https curl lsb-release \
    && curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list \
    && apt-get update \
    && if [ -z "$PHP_SOURCE_VERSION" ]; then \
    # Install PHP packages
    apt-get install -y --no-install-recommends \
    php8.3-bcmath \
    php8.3-cli \
    php8.3-common \
    php8.3-ctype \
    php8.3-curl \
    php8.3-dom \
    php8.3-fileinfo \
    php8.3-fpm \
    php8.3-gd \
    php8.3-iconv \
    php8.3-imap \
    php8.3-intl \
    php8.3-ldap \
    php8.3-mbstring \
    php8.3-mysqlnd \
    php8.3-opcache \
    php8.3-redis \
    php8.3-soap \
    php8.3-sqlite3 \
    php8.3-xml \
    php8.3-zip \
    php-common \
    php8.3 \
    ; else \
    # PHP_SOURCE_VERSION set: PHP comes from builder-php-src (see stage2). SURY stays
    # configured only because libc-client2007e (imap) is not in Debian; pinned low
    # so nothing else is taken from it.
    printf 'Package: *\nPin: origin packages.sury.org\nPin-Priority: 100\n' > /etc/apt/preferences.d/98sury \
    ; fi \
    # Clean up PHP installation
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/*

# Install nginx with OpenTelemetry module (inlined for proper dependency resolution)
ARG NGINX_VERSION="1.30.7"
ARG NGINX_GPG_KEY_FINGERPRINTS="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62:8540A6F18833A80E9C1653A42FD21310B49F6B46:9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3"

RUN apt-get update \
    && apt-get install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring \
    && curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor > /usr/share/keyrings/nginx-archive-keyring.gpg \
    # verify key is what we expect
    && key_fingerprints="$(gpg --show-keys --with-colons /usr/share/keyrings/nginx-archive-keyring.gpg | awk -F: '$1 == "fpr" { print $10 }' | sort | paste -s -d:)" \
    && [ "$NGINX_GPG_KEY_FINGERPRINTS" = "$key_fingerprints" ] || { \
    echo "nginx key fingerprints do not match"; \
    exit 1; \
    } \
    && printf "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/debian %s nginx\n" "$(lsb_release -cs)" | tee /etc/apt/sources.list.d/nginx.list \
    && printf "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx \
    && apt-get update \
    && apt-get install -y "nginx=${NGINX_VERSION}-*" "nginx-module-otel=${NGINX_VERSION}+*" \
    # Clean up nginx installation
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    # Nginx package creates user and directories automatically - no manual setup needed
    && ls -la /usr/sbin/nginx /etc/nginx /usr/lib/nginx/modules/

# stage2 -- packages from other images
FROM stage1 AS stage2
COPY --from=builder-php-exts /usr/lib/php/20230831/protobuf.so /usr/lib/php/20230831/protobuf.so
COPY --from=builder-php-exts /usr/lib/php/20230831/opentelemetry.so /usr/lib/php/20230831/opentelemetry.so
COPY --from=builder-php-exts /usr/lib/php/20230831/grpc.so /usr/lib/php/20230831/grpc.so
# PHP_SOURCE_VERSION set: PHP built from source (cli, fpm, extensions, phpenmod/phpdismod),
# overlaying the SURY-built .so files copied above with ones built against that PHP.
# PHP_SOURCE_VERSION empty: /out is empty and this is a no-op.
COPY --from=builder-php-src /out/ /
# Runtime shared libs of the source-built PHP (no-op unless the file above exists)
RUN if [ -f /php-src-runtime-deps ]; then \
    apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $(cat /php-src-runtime-deps) \
    && rm -f /php-src-runtime-deps \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/*; \
    fi
COPY --from=ghcr.io/jqlang/jq:1.8.1 /jq /usr/local/bin/jq
# Security-patched packages already installed in stage1
COPY --from=builder-go-binaries /usr/local/bin/gomplate /usr/local/bin/gomplate
# Nginx installed directly in stage1 - no COPY needed
COPY --from=composer:2.10.3 /usr/bin/composer /usr/local/bin/composer
COPY --from=timberio/vector:0.60.0-debian /usr/bin/vector /usr/local/bin/vector
COPY --from=builder-smokescreen /out/smokescreen /usr/local/bin/smokescreen
COPY --from=node:22.23.5-bookworm /usr/local/bin /usr/local/bin
COPY --from=node:22.23.5-bookworm /usr/local/lib/node_modules /usr/local/lib/node_modules
# Upgrade npm -- the npm bundled with node ships a vulnerable picomatch
# (CVE-2026-33671); this pinned npm pulls the patched picomatch 4.0.4.
ARG NPM_VERSION="11.19.0"
ARG TSX_VERSION="4.22.4"
# tsx vendors esbuild; force patched 0.28.1 (GHSA-gv7w-rqvm-qjhr, GHSA-g7r4-m6w7-qqqr)
ARG ESBUILD_VERSION="0.28.1"
# npm ships its whole dependency tree bundled, so no npm release carries patched
# copies of these -- they can only be fixed by overwriting them in place:
#   tar             -- CVE-2026-59871/59873/59874, GHSA-vmf3-w455-68vh,
#                      GHSA-gvwx-54wh-qm9j, GHSA-r292-9mhp-454m
#   ip-address      -- CVE-2026-54272, GHSA-mwp4-54f8-5fhr, GHSA-4xrf-jv44-h6hh,
#                      GHSA-2vr4-cq9g-pvrc, GHSA-rpw4-54j3-4h4q (SSRF)
#   brace-expansion -- CVE-2026-69152, CVE-2026-13149
#   undici          -- prototype pollution (AIKIDO-2026-10385/10369), plus
#                      CVE-2026-12151 (DoS), CVE-2026-9679 (CRLF) and an
#                      infinite-loop DoS fixed only in undici 8, so this is a
#                      major bump for node-gyp
ARG NPM_TAR_VERSION="7.5.22"
ARG NPM_IP_ADDRESS_VERSION="10.7.1"
ARG NPM_BRACE_EXPANSION_VERSION="5.0.12"
ARG NPM_UNDICI_VERSION="8.12.3"
RUN set -eu \
    && npm install --global "npm@${NPM_VERSION}" \
    && npm install --global "tsx@${TSX_VERSION}" \
    && npm install --prefix /usr/local/lib/node_modules/tsx --save-exact "esbuild@${ESBUILD_VERSION}" \
    && /usr/local/lib/node_modules/tsx/node_modules/esbuild/bin/esbuild --version \
    # replace npm's bundled copies of the vulnerable packages with patched ones
    && npm_bundle=/usr/local/lib/node_modules/npm/node_modules \
    && tmp="$(mktemp -d)" \
    && for spec in "tar@${NPM_TAR_VERSION}" \
    "ip-address@${NPM_IP_ADDRESS_VERSION}" \
    "brace-expansion@${NPM_BRACE_EXPANSION_VERSION}" \
    "undici@${NPM_UNDICI_VERSION}"; do \
    pkg="${spec%@*}"; \
    [ -d "${npm_bundle}/${pkg}" ] || { echo "npm no longer bundles ${pkg} -- drop this patch"; exit 1; }; \
    ( cd "$tmp" && npm pack --silent "$spec" >/dev/null ) \
    && rm -rf "${npm_bundle:?}/${pkg}" \
    && mkdir -p "${npm_bundle}/${pkg}" \
    && tar -xzf "$tmp"/*.tgz -C "${npm_bundle}/${pkg}" --strip-components=1 \
    && rm -f "$tmp"/*.tgz \
    && node -p "'patched '+require('${npm_bundle}/'+'${pkg}'+'/package.json').version+' ${pkg}'"; \
    done \
    && rm -rf "$tmp" \
    # smoke-test npm itself and node-gyp, the only consumer of the undici 6 -> 7 bump
    && npm --version \
    && node -e "require('${npm_bundle}/node-gyp/lib/download.js')" \
    && node "${npm_bundle}/node-gyp/bin/node-gyp.js" --version

# Install system packages needed for verification and runtime
RUN apt-get update && apt-get install -y \
    sqlite3 libsqlite3-0 \
    curl libcurl4 libcurl4-openssl-dev \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Final security upgrade -- the early apt-get upgrade in stage1 runs before
# php/nginx/node and the packages above are installed, so transitively-pulled
# packages (e.g. libnghttp2, python3, libgnutls*) can still carry CVEs.
# Re-run upgrade against fresh lists so all installed packages get the latest
# Debian security patches (+deb13uN).
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/*

# Pin patched security releases in a dedicated layer; busts stale apt-layer
# cache that can freeze earlier stages at a vulnerable version.
#   openssl stack  -- CVE-2026-63072 (memory corruption, crash/RCE, PoC),
#                     CVE-2026-63076 (NULL deref), CVE-2026-18798 (double free)
#   libssh2 (via libcurl) -- CVE-2026-55200 (use-after-free, PoC exists)
#   libheif (via libgd3 <- php8.3-gd) -- CVE-2026-62289, CVE-2026-62292
# Keep OPENSSL_VERSION in step with the libssl-dev version in trixie-security:
# libssh2-1-dev pulls in libssl-dev, which requires a matching libssl3t64.
ARG OPENSSL_VERSION="3.5.7-1~deb13u3"
ARG LIBSSH2_VERSION="1.11.1-1+deb13u2"
ARG LIBHEIF_VERSION="1.23.6-2~deb13u1"
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "openssl=${OPENSSL_VERSION}" \
    "libssl3t64=${OPENSSL_VERSION}" \
    "openssl-provider-legacy=${OPENSSL_VERSION}" \
    "libssh2-1t64=${LIBSSH2_VERSION}" \
    "libssh2-1-dev=${LIBSSH2_VERSION}" \
    "libheif1=${LIBHEIF_VERSION}" \
    "libheif-plugin-dav1d=${LIBHEIF_VERSION}" \
    "libheif-plugin-libde265=${LIBHEIF_VERSION}" \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    && openssl version -v \
    && dpkg-query -W libssh2-1t64 \
    && dpkg-query -W libheif1 libheif-plugin-dav1d libheif-plugin-libde265

# util-linux stack -- CVE-2026-53612/53613/53614/53615 (low). Fixed in
# 2.41.5-0+deb13u1. Scoped --only-upgrade (not exact pins) because bsdutils
# carries an epoch; let apt resolve the newest deb13uN for the whole source set.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade --no-install-recommends \
    bsdutils \
    util-linux \
    liblastlog2-2 \
    libmount1 \
    libsmartcols1 \
    libuuid1 \
    apt \
    libapt-pkg7.0 \
    apt-transport-https \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    && dpkg-query -W bsdutils util-linux libmount1 libsmartcols1 libuuid1 liblastlog2-2

# Verify installations
RUN ldconfig \
    # Verify our system versions are working
    && /usr/local/bin/jq --version \
    && sqlite3 --version \
    && curl --version \
    && rsync --version \
    && openssl version \
    && echo "System packages verified successfully"
RUN echo 'Dpkg::Options {' > /etc/apt/apt.conf.d/01autoconf \
    && echo '   "--force-confdef";' >> /etc/apt/apt.conf.d/01autoconf \
    && echo '   "--force-confold";' >> /etc/apt/apt.conf.d/01autoconf \
    && echo '}' >> /etc/apt/apt.conf.d/01autoconf \
    # Create proper symlinks for our security-patched libraries to avoid ldconfig warnings
    && cd /usr/local/lib \
    && for base in libexpat libaom libz libtiff; do \
    sofile=$(ls -1 ${base}.so.* 2>/dev/null | sort -V | tail -n 1); \
    if [ -n "$sofile" ] && [ ! -e "${base}.so" ]; then \
    ln -sf "$sofile" "${base}.so"; \
    fi; \
    done \
    && ldconfig

RUN sed -i 's/providers = provider_sect/providers = provider_sect\n\
ssl_conf = ssl_sect\n\
\n\
[ssl_sect]\n\
system_default = system_default_sect\n\
\n\
[system_default_sect]\n\
Options = UnsafeLegacyRenegotiation/' /etc/ssl/openssl.cnf

RUN set -e \
    # Create PHP configuration files
    && printf '; priority=20\nextension=protobuf.so' > /etc/php/8.3/mods-available/protobuf.ini \
    && printf '; priority=20\nextension=grpc.so' > /etc/php/8.3/mods-available/grpc.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/deskpro.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/deskpro-otel.ini \
    # Enable PHP modules
    && phpenmod protobuf grpc deskpro deskpro-otel \
    && phpdismod phar \
    && rm -f /etc/php/8.3/fpm/pool.d/www.conf \
    # Preserve nginx configuration from official package
    && chmod 0755 /etc/nginx /etc/nginx/conf.d \
    && rm -f /etc/nginx/conf.d/default.conf

# Remove the emSign root CAs from the system trust list. Debian's ca-certificates
# package ships them; mark them "!" in /etc/ca-certificates.conf and regenerate the
# bundle. Runs after the last apt step in this stage so a later ca-certificates
# install/upgrade cannot re-enable them.
RUN sed -i -E 's#^(mozilla/emSign_.*\.crt)$#!\1#' /etc/ca-certificates.conf \
    && update-ca-certificates --fresh

# build -- final stage adds our custom stuff
FROM stage2 AS build
COPY etc /etc/
COPY usr/local/bin /usr/local/bin/
COPY usr/local/lib /usr/local/lib/
COPY usr/local/sbin /usr/local/sbin/
COPY usr/local/share/deskpro /usr/local/share/deskpro/

RUN set -e \
    # dp_app user is used when we run any app code (e.g. php-fpm, CLI tasks, etc)
    && addgroup --gid 1083 dp_app \
    && adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1083 --gid 1083 dp_app \
    # vector user for logs
    && addgroup --gid 1084 vector \
    && adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1084 --gid 1084 vector \
    # add vector to adm group so it can read logs
    && usermod -a -G adm vector \
    # we run nginx as its own user. The nginx package creates the user with
    # a distro-default UID/GID, so force it to our fixed UID 1085 if it exists.
    && if getent group nginx >/dev/null 2>&1; then groupmod -g 1085 nginx; else addgroup --gid 1085 nginx; fi \
    && if id nginx >/dev/null 2>&1; then usermod -u 1085 -g 1085 nginx; else adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1085 --gid 1085 nginx; fi \
    # smokescreen runs as its own unprivileged user -- it never needs root
    && addgroup --gid 1086 smokescreen \
    && adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1086 --gid 1086 smokescreen \
    # initialize dirs and owners
    && mkdir -p /var/log/nginx /var/log/php /var/log/deskpro /var/log/supervisor /var/lib/vector \
    && mkdir -p /srv/deskpro/INSTANCE_DATA/deskpro-config.d \
    && mkdir -p /etc/smokescreen && chmod 0755 /etc/smokescreen \
    && chown root:root /usr/local/bin/vector /usr/local/bin/smokescreen \
    && chown vector:adm /var/lib/vector \
    && chown nginx:adm /var/log/nginx \
    && chown dp_app:adm /var/log/php /var/log/deskpro \
    && chmod -R 0775 /var/log/php /var/log/deskpro \
    # set group sticky bit on these dirs so
    # new logs get created with adm group (so vector can read them)
    && chmod g+s /var/log/nginx /var/log/php /var/log/deskpro \
    # extract var names from our reference list
    # (these lists are used from various helper scripts or entrypoint scripts)
    && jq -r '.[] | select(.isPrivate|not) | .name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-public-var-list \
    && jq -r '.[] | select(.isPrivate) | .name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-private-var-list \
    && jq -r '.[] | select(.setEnv) | .name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-setenv-var-list \
    && jq -r '.[].name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-var-list \
    && chmod 644 /usr/local/share/deskpro/*

RUN grep -q '^VERSION_ID=' /etc/os-release || echo 'VERSION_ID="12"' >> /etc/os-release

HEALTHCHECK --interval=10s --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/healthcheck

# http/https
EXPOSE 80/tcp
EXPOSE 443/tcp

# http/https with proxy protocol
EXPOSE 9080/tcp
EXPOSE 9443/tcp

# http that serves status page
EXPOSE 10001/tcp

# Root directory for all "custom mount" dirs
ENV CUSTOM_MOUNT_BASEDIR="/deskpro"

# The base config file to use
ENV DESKPRO_CONFIG_FILE="/usr/local/share/deskpro/templates/deskpro-config.php.tmpl"

# Log level for entrypoint scripts that controls which logs are printed to stderr
ENV BOOT_LOG_LEVEL="INFO"
ENV BOOT_LOG_LEVEL_EXEC="WARNING"

# Possible values: stdout, dir, cloudwatch
# When empty (default) it will be set to "dir" if LOGS_EXPORT_DIR is set or "stdout" if not
ENV LOGS_EXPORT_TARGET=""

# If this is set, then logs will be written out to this directory
# (if CUSTOM_MOUNT_BASEDIR/logs exists, then this will be set to that dir if not already set)
ENV LOGS_EXPORT_DIR=""

# The filename to use when writing logs to LOGS_EXPORT_DIR
ENV LOGS_EXPORT_FILENAME="{{.container_name}}-{{.log_group}}.log"

# Enable ("1" or "true") to enable fast shutdown (don't wait for all processes to finish gracefully)
ENV FAST_SHUTDOWN="0"

# GID to use for exported log files. By default, logs will be owned by the vector group (GID 1084).
ENV LOGS_GID=""

ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
CMD ["web"]
