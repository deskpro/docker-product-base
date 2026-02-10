# builder stage -- builds PHP packages
# outputs: /usr/lib/php/20230831/protobuf.so
# outputs: /usr/lib/php/20230831/opentelemetry.so
# outputs: /usr/lib/newrelic-php5/agent/x64/newrelic-20230831.so
# outputs: /usr/bin/newrelic-daemon
FROM debian:13.3-slim AS builder-php-exts
ENV NEW_RELIC_AGENT_VERSION=12.4.0.29
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
    php-pear \
    && pecl install opentelemetry protobuf \
    && curl -L https://download.newrelic.com/php_agent/archive/${NEW_RELIC_AGENT_VERSION}/newrelic-php5-${NEW_RELIC_AGENT_VERSION}-linux.tar.gz | tar -C /tmp -zx \
    && NR_INSTALL_USE_CP_NOT_LN=1 NR_INSTALL_SILENT=true /tmp/newrelic-php5-${NEW_RELIC_AGENT_VERSION}-linux/newrelic-install install \
    && rm -rf /var/lib/apt/lists/* /tmp/newrelic-php5-* /tmp/nrinstall*

# Use pre-built gomplate v5.0.0 binary to avoid vulnerable indirect dependencies
FROM debian:13.3-slim AS builder-go-binaries
RUN apt-get update && apt-get install -y curl ca-certificates \
    && TARGET_ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/') \
    && echo "Downloading gomplate v5.0.0 for architecture: $TARGET_ARCH" \
    && curl -fsSL "https://github.com/hairyhenderson/gomplate/releases/download/v5.0.0/gomplate_linux-${TARGET_ARCH}" -o /usr/local/bin/gomplate \
    && chmod +x /usr/local/bin/gomplate \
    && /usr/local/bin/gomplate --version

# Install nginx from official repository with OpenTelemetry module
FROM debian:13.3-slim AS builder-nginx
ARG NGINX_VERSION="1.28.2"
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
    && apt-get install -y nginx=${NGINX_VERSION}-* nginx-module-otel \
    && mkdir -p /var/cache/nginx /usr/lib/nginx/modules \
    && ls -la /usr/sbin/nginx /etc/nginx /usr/lib/nginx/modules/

# builder stage -- builds essential security-patched packages from source
# SIMPLIFIED: Use system packages from debian:12.13-slim instead of source builds
FROM debian:13.3-slim AS builder-security-packages
ARG USE_SYSTEM_PACKAGES_ONLY=true

# If using system packages only, just install the latest available packages
RUN if [ "$USE_SYSTEM_PACKAGES_ONLY" = "true" ]; then \
    echo "Using debian:12.13-slim system packages instead of source builds" \
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
FROM debian:13.3-slim AS stage1
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
    # Install system packages - debian:12.13-slim has latest security updates
    && apt-get update \
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
    python3-pip \
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
RUN export DEBIAN_FRONTEND=noninteractive \
    # Add PHP repository for latest versions
    && apt-get update \
    && apt-get install -y ca-certificates apt-transport-https curl lsb-release \
    && curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list \
    && apt-get update \
    # Install PHP packages
    && apt-get install -y --no-install-recommends \
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
    php8.3-soap \
    php8.3-sqlite3 \
    php8.3-xml \
    php8.3-zip \
    php-common \
    php8.3 \
    # Clean up
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    # Create nginx user and directories for the source-built nginx
    && groupadd -r nginx 2>/dev/null || groupadd nginx \
    && useradd -r -g nginx -s /sbin/nologin -d /var/cache/nginx -c nginx nginx 2>/dev/null || useradd -s /sbin/nologin -d /var/cache/nginx -c nginx -g nginx nginx \
    && mkdir -p /var/cache/nginx /var/log/nginx \
    && chown -R nginx:nginx /var/cache/nginx /var/log/nginx

# stage2 -- packages from other images
FROM stage1 AS stage2
COPY --from=builder-php-exts /usr/lib/php/20230831/protobuf.so /usr/lib/php/20230831/protobuf.so
COPY --from=builder-php-exts /usr/lib/php/20230831/opentelemetry.so /usr/lib/php/20230831/opentelemetry.so
COPY --from=builder-php-exts /usr/lib/php/20230831/newrelic.so /usr/lib/php/20230831/newrelic.so
COPY --from=builder-php-exts /usr/bin/newrelic-daemon /usr/local/bin/newrelic-daemon
COPY --from=ghcr.io/jqlang/jq:1.8.1 /jq /usr/local/bin/jq
# Security-patched packages already installed in stage1
COPY --from=builder-go-binaries /usr/local/bin/gomplate /usr/local/bin/gomplate
COPY --from=builder-nginx /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder-nginx /etc/nginx /etc/nginx
COPY --from=builder-nginx /usr/lib/nginx /usr/lib/nginx
COPY --from=composer:2.9.2 /usr/bin/composer /usr/local/bin/composer
COPY --from=timberio/vector:0.51.1-debian /usr/bin/vector /usr/local/bin/vector
COPY --from=node:22-bookworm /usr/local/bin /usr/local/bin
COPY --from=node:22-bookworm /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN npm install --global tsx

# Install system packages needed for verification and runtime
RUN apt-get update && apt-get install -y \
    sqlite3 libsqlite3-0 \
    curl libcurl4 libcurl4-openssl-dev \
    rsync \
    && rm -rf /var/lib/apt/lists/*

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
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/deskpro.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/deskpro-otel.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/newrelic.ini \
    # Enable PHP modules
    && phpenmod protobuf deskpro deskpro-otel newrelic \
    && phpdismod phar \
    && rm -f /etc/php/8.3/fpm/pool.d/www.conf \
    # Preserve nginx configuration from official package
    && chmod 0755 /etc/nginx /etc/nginx/conf.d

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
    # we run nginx as its own user
    && (getent group nginx >/dev/null 2>&1 || addgroup --gid 1085 nginx) \
    && (id nginx >/dev/null 2>&1 || adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1085 --gid 1085 nginx) \
    # initialize dirs and owners
    && mkdir -p /var/log/nginx /var/log/php /var/log/deskpro /var/log/supervisor /var/lib/vector /var/log/newrelic \
    && mkdir -p /srv/deskpro/INSTANCE_DATA/deskpro-config.d \
    && chown root:root /usr/local/bin/vector \
    && chown vector:adm /var/lib/vector \
    && chown nginx:adm /var/log/nginx \
    && chown dp_app:adm /var/log/php /var/log/deskpro /var/log/newrelic \
    && chmod -R 0775 /var/log/php /var/log/deskpro /var/log/newrelic \
    # set group sticky bit on these dirs so
    # new logs get created with adm group (so vector can read them)
    && chmod g+s /var/log/nginx /var/log/php /var/log/deskpro /var/log/newrelic \
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
