# builder stage -- builds PHP packages
# outputs: /usr/lib/php/20230831/protobuf.so
# outputs: /usr/lib/php/20230831/opentelemetry.so
# outputs: /usr/lib/newrelic-php5/agent/x64/newrelic-20230831.so
# outputs: /usr/bin/newrelic-daemon
FROM debian:12.11-slim AS builder-php-exts
ENV NEW_RELIC_AGENT_VERSION=11.6.0.19
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates apt-transport-https software-properties-common curl lsb-release build-essential \
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

# builder stage -- builds security-patched packages from source
# outputs: /usr/local/bin/sqlite3, /usr/local/lib/libsqlite3.so (CVE-2025-6965 fix)
# outputs: /usr/local/lib/libexpat.so.* (CVE-2023-52425 fix)
# outputs: /usr/local/lib/libaom.so.* (CVE-2023-6879 fix)
# outputs: /usr/local/lib/libz.so.* (CVE-2023-45853 fix)
# outputs: /usr/local/lib/libtiff.so.* (CVE-2023-52355 fix)
FROM debian:12.11-slim AS builder-security-packages
ARG TARGETPLATFORM
# Debug TARGETPLATFORM value
RUN echo "Building for platform: ${TARGETPLATFORM:-unknown}" && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    unzip \
    pkg-config \
    yasm \
    nasm \
    file

# Install latest SQLite from source (CVE-2025-6965 fix - requires 3.50.2+)
# Download the latest version with fallback support
RUN CURRENT_YEAR=$(date +%Y) \
    && PREV_YEAR=$((CURRENT_YEAR-1)) \
    && LATEST_SQLITE=$(wget -qO- "https://www.sqlite.org/download.html" | grep -o "sqlite-amalgamation-[0-9]\+\.zip" | sort -V | tail -n 1) \
    && SQLITE_VERSION=$(echo $LATEST_SQLITE | grep -o "[0-9]\+") \
    && (wget -q --spider "https://www.sqlite.org/${CURRENT_YEAR}/${LATEST_SQLITE}" && \
    wget "https://www.sqlite.org/${CURRENT_YEAR}/${LATEST_SQLITE}" || \
    wget "https://www.sqlite.org/${PREV_YEAR}/${LATEST_SQLITE}") \
    && unzip sqlite-amalgamation-${SQLITE_VERSION}.zip \
    && cd sqlite-amalgamation-${SQLITE_VERSION} \
    && gcc -O2 -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_GEOPOLY \
    -o /usr/local/bin/sqlite3 shell.c sqlite3.c -ldl -lm -lpthread \
    && gcc -O2 -fPIC -shared -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_GEOPOLY \
    -o /usr/local/lib/libsqlite3.so sqlite3.c -ldl -lm -lpthread \
    && cd .. && rm -rf sqlite-amalgamation-${SQLITE_VERSION}* \
    && echo "SQLite installation completed successfully" \
    && /usr/local/bin/sqlite3 --version

# Install latest expat from source (CVE-2023-52425 fix)
RUN EXPAT_VERSION="2.7.1" \
    && wget "https://github.com/libexpat/libexpat/releases/download/R_$(echo ${EXPAT_VERSION} | tr '.' '_')/expat-${EXPAT_VERSION}.tar.bz2" \
    && tar -xjf expat-${EXPAT_VERSION}.tar.bz2 \
    && cd expat-${EXPAT_VERSION} \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf expat-${EXPAT_VERSION}* \
    && echo "Expat installation completed successfully" \
    && ls -la /usr/local/lib/libexpat.so*

# Install latest libaom from source (CVE-2023-6879 fix)
RUN git clone --depth 1 --branch v3.12.1 https://aomedia.googlesource.com/aom \
    && cd aom \
    && mkdir aom_build && cd aom_build \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DBUILD_SHARED_LIBS=1 -DENABLE_TESTS=0 -DENABLE_EXAMPLES=0 .. \
    && make -j$(nproc) \
    && make install \
    && cd ../.. && rm -rf aom \
    && echo "libaom installation completed successfully" \
    && ls -la /usr/local/lib/libaom.so*

# Install latest zlib from source (CVE-2023-45853 fix - MiniZip vulnerability) - MUST be before OpenSSL
RUN ZLIB_VERSION="1.3.1" \
    && wget "https://github.com/madler/zlib/archive/v${ZLIB_VERSION}.tar.gz" \
    && tar -xzf v${ZLIB_VERSION}.tar.gz \
    && cd zlib-${ZLIB_VERSION} \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf zlib-${ZLIB_VERSION}* v${ZLIB_VERSION}.tar.gz \
    && echo "zlib installation completed successfully" \
    && ls -la /usr/local/lib/libz.so*

# Install latest OpenSSL (addresses various OpenSSL vulnerabilities)
RUN echo "Installing latest OpenSSL from Debian security updates..." \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    openssl \
    libssl-dev \
    libssl3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && echo "OpenSSL installation completed successfully" \
    && openssl version \
    && echo "OpenSSL libraries:" \
    && find /usr/lib -name "libssl*" -o -name "libcrypto*" | head -10

# Install latest libtiff from source (CVE-2023-52355 fix)
RUN LIBTIFF_VERSION="4.7.0" \
    && wget "https://download.osgeo.org/libtiff/tiff-${LIBTIFF_VERSION}.tar.gz" \
    && tar -xzf tiff-${LIBTIFF_VERSION}.tar.gz \
    && cd tiff-${LIBTIFF_VERSION} \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf tiff-${LIBTIFF_VERSION}* \
    && echo "libtiff installation completed successfully" \
    && ls -la /usr/local/lib/libtiff.so*

# Verify all installations
RUN echo "Verifying all security package installations" \
    && /usr/local/bin/sqlite3 --version \
    && echo "Checking for library files:" \
    && find /usr/local/lib -name "libexpat.so*" || true \
    && find /usr/local/lib -name "libaom.so*" || true \
    && find /usr/local/lib -name "libssl.so*" || true \
    && find /usr/local/lib -name "libcrypto.so*" || true \
    && find /usr/local/lib -name "libz.so*" || true \
    && find /usr/local/lib -name "libtiff.so*" || true \
    && echo "Verification completed - skipping OpenSSL version check"

# stage1 -- debian with security patches first, then packages
FROM debian:12.11-slim AS stage1
ENV TZ=UTC
WORKDIR /srv/deskpro
USER root

# First: Copy and install security-patched packages BEFORE installing dependent packages
COPY --from=builder-security-packages /usr/local/bin/sqlite3 /usr/local/bin/sqlite3
COPY --from=builder-security-packages /usr/local/lib/libsqlite3.so /usr/local/lib/libsqlite3.so
COPY --from=builder-security-packages /usr/local/lib/libexpat.so* /usr/local/lib/
COPY --from=builder-security-packages /usr/local/include/expat*.h /usr/local/include/
COPY --from=builder-security-packages /usr/local/lib/libaom.so* /usr/local/lib/
COPY --from=builder-security-packages /usr/local/include/aom /usr/local/include/
COPY --from=builder-security-packages /usr/local/lib/libz.so* /usr/local/lib/
COPY --from=builder-security-packages /usr/local/include/zlib.h /usr/local/include/
COPY --from=builder-security-packages /usr/local/include/zconf.h /usr/local/include/
COPY --from=builder-security-packages /usr/local/lib/libtiff.so* /usr/local/lib/
COPY --from=builder-security-packages /usr/local/include/tiff*.h /usr/local/include/

# Configure dynamic linker for security patches and remove vulnerable system packages FIRST
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/usr-local.conf \
    && ldconfig \
    # Remove vulnerable system packages BEFORE installing packages that might depend on them
    && apt-get update \
    && for pkg in libsqlite3-0 libexpat1 libaom3; do \
    if ! apt-get remove -y "$pkg"; then \
    if ! dpkg -s "$pkg" 2>&1 | grep -q "is not installed"; then \
    echo "Failed to remove $pkg"; \
    exit 1; \
    fi; \
    fi; \
    done \
    && ldconfig

# Now install packages - they will use our security-patched versions
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-install-suggests ca-certificates apt-transport-https software-properties-common curl lsb-release \
    && curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
    && sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list' \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-install-suggests -y \
    bash \
    bc \
    curl \
    default-mysql-client \
    git \
    libfcgi-bin \
    libldap-common \
    nano \
    nginx \
    vim-tiny \
    openssl \
    libssl-dev \
    libssl3 \
    poppler-utils \
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
    ripgrep \
    rsync \
    sudo \
    supervisor \
    tzdata \
    # Add Debian testing repository for complex system packages (excluding vulnerable packages we build from source)
    && echo 'deb http://deb.debian.org/debian testing main' >> /etc/apt/sources.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -t testing \
    libldap-2.5-0 libldap-common perl-base perl \
    python3-pip \
    && find /usr/lib/python3.11 -type f -name '*.py[co]' -delete -o -type d -name __pycache__ -delete \
    # Install secure Python packages via pip (CVE-2023-50782, CVE-2025-47273 fixes)
    && pip3 install --break-system-packages "setuptools>=78.1.1" "cryptography>=42.0.0" \
    # Update CPAN for Perl security (CVE-2023-31484 fix) - simplified approach
    && perl -MCPAN -e 'install App::cpanminus' \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/bin/mariadb-access /usr/bin/mariadb-admin /usr/bin/mariadb-analyze /usr/bin/mariadb-check /usr/bin/mariadb-binlog /usr/bin/mariadb-conv /usr/bin/mariadb-convert-table-format /usr/bin/mariadb-find-rows /usr/bin/mariadb-fix-extensions /usr/bin/mariadb-hotcopy /usr/bin/mariadb-import /usr/bin/mariadb-optimize /usr/bin/mariadb-plugin /usr/bin/mariadb-repair /usr/bin/mariadb-report /usr/bin/mariadb-secure-installation /usr/bin/mariadb-setpermission /usr/bin/mariadb-show /usr/bin/mariadb-slap /usr/bin/mariadb-tzinfo-to-sql /usr/bin/mariadb-waitpid /usr/bin/mariadbcheck \
    && ln -s /usr/bin/vim.tiny /usr/bin/vim

# stage2 -- packages from other images
FROM stage1 AS stage2
COPY --from=builder-php-exts /usr/lib/php/20230831/protobuf.so /usr/lib/php/20230831/protobuf.so
COPY --from=builder-php-exts /usr/lib/php/20230831/opentelemetry.so /usr/lib/php/20230831/opentelemetry.so
COPY --from=builder-php-exts /usr/lib/php/20230831/newrelic.so /usr/lib/php/20230831/newrelic.so
COPY --from=builder-php-exts /usr/bin/newrelic-daemon /usr/local/bin/newrelic-daemon
COPY --from=ghcr.io/jqlang/jq:1.8.1 /jq /usr/local/bin/jq
# Security-patched packages already installed in stage1
COPY --from=hairyhenderson/gomplate:v3.11.5 /gomplate /usr/local/bin/gomplate
COPY --from=composer:2.5.8 /usr/bin/composer /usr/local/bin/composer
COPY --from=timberio/vector:0.46.1-debian /usr/bin/vector /usr/local/bin/vector
COPY --from=node:20.19-bookworm /usr/local/bin /usr/local/bin
COPY --from=node:20.19-bookworm /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN npm install --global tsx

#  verify installations
RUN ldconfig \
    # Verify our security-patched versions are working
    && /usr/local/bin/jq --version \
    && /usr/local/bin/sqlite3 --version \
    && openssl version \
    && echo "Verifying security-patched libraries:" \
    && ls -la /usr/local/lib/libexpat.so* \
    && ls -la /usr/local/lib/libaom.so*

# Configure apt to handle config file updates automatically and fix library symlinks
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
    && printf '; priority=20\nextension=protobuf.so' > /etc/php/8.3/mods-available/protobuf.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/deskpro.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/deskpro-otel.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/newrelic.ini \
    && phpenmod protobuf deskpro deskpro-otel newrelic \
    && phpdismod phar \
    && rm /etc/php/8.3/fpm/pool.d/www.conf \
    && mv /etc/nginx/mime.types /tmp/mime.types \
    && rm -rf /etc/nginx \
    && mkdir -p /etc/nginx/conf.d \
    && chmod 0755 /etc/nginx /etc/nginx/conf.d \
    && mv /tmp/mime.types /etc/nginx

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
    && addgroup --gid 1085 nginx \
    && adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1085 --gid 1085 nginx \
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
ENV CUSTOM_MOUNT_BASEDIR "/deskpro"

# The base config file to use
ENV DESKPRO_CONFIG_FILE "/usr/local/share/deskpro/templates/deskpro-config.php.tmpl"

# Log level for entrypoint scripts that controls which logs are printed to stderr
ENV BOOT_LOG_LEVEL "INFO"
ENV BOOT_LOG_LEVEL_EXEC "WARNING"

# Possible values: stdout, dir, cloudwatch
# When empty (default) it will be set to "dir" if LOGS_EXPORT_DIR is set or "stdout" if not
ENV LOGS_EXPORT_TARGET ""

# If this is set, then logs will be written out to this directory
# (if CUSTOM_MOUNT_BASEDIR/logs exists, then this will be set to that dir if not already set)
ENV LOGS_EXPORT_DIR ""

# The filename to use when writing logs to LOGS_EXPORT_DIR
ENV LOGS_EXPORT_FILENAME "{{.container_name}}-{{.log_group}}.log"

# Enable ("1" or "true") to enable fast shutdown (don't wait for all processes to finish gracefully)
ENV FAST_SHUTDOWN="0"

# GID to use for exported log files. By default, logs will be owned by the vector group (GID 1084).
ENV LOGS_GID ""

ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
CMD ["web"]
