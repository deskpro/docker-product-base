FROM debian:12.2-slim as builder-php-exts
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates apt-transport-https software-properties-common curl lsb-release \
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
    && rm -rf /var/lib/apt/lists/*
# outputs: /usr/lib/php/20230831/protobuf.so
# outputs: /usr/lib/php/20230831/opentelemetry.so

FROM debian:12.2-slim
ENV TZ=UTC
WORKDIR /srv/deskpro
USER root

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
    jq \
    libfcgi-bin \
    libldap-common \
    nano \
    nginx \
    vim-tiny \
    openssl \
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
    php8.3-xml \
    php8.3-zip \
    ripgrep \
    rsync \
    sudo \
    supervisor \
    tzdata \
    && find /usr/lib/python3.11 -type f -name '*.py[co]' -delete -o -type d -name __pycache__ -delete \
    && apt-get -y autoremove && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/bin/mariadb-access /usr/bin/mariadb-admin /usr/bin/mariadb-analyze /usr/bin/mariadb-check /usr/bin/mariadb-binlog /usr/bin/mariadb-conv /usr/bin/mariadb-convert-table-format /usr/bin/mariadb-find-rows /usr/bin/mariadb-fix-extensions /usr/bin/mariadb-hotcopy /usr/bin/mariadb-import /usr/bin/mariadb-optimize /usr/bin/mariadb-plugin /usr/bin/mariadb-repair /usr/bin/mariadb-report /usr/bin/mariadb-secure-installation /usr/bin/mariadb-setpermission /usr/bin/mariadb-show /usr/bin/mariadb-slap /usr/bin/mariadb-tzinfo-to-sql /usr/bin/mariadb-waitpid /usr/bin/mariadbcheck

RUN sed -i 's/providers = provider_sect/providers = provider_sect\n\
ssl_conf = ssl_sect\n\
\n\
[ssl_sect]\n\
system_default = system_default_sect\n\
\n\
[system_default_sect]\n\
Options = UnsafeLegacyRenegotiation/' /etc/ssl/openssl.cnf

COPY --from=builder-php-exts /usr/lib/php/20230831/protobuf.so /usr/lib/php/20230831/protobuf.so
COPY --from=builder-php-exts /usr/lib/php/20230831/opentelemetry.so /usr/lib/php/20230831/opentelemetry.so

COPY --from=hairyhenderson/gomplate:v3.11.5 /gomplate /usr/local/bin/gomplate
COPY --from=composer:2.5.8 /usr/bin/composer /usr/local/bin/composer
COPY --from=timberio/vector:0.31.0-debian /usr/bin/vector /usr/local/bin/vector
COPY --from=oven/bun:1.0.14-debian /usr/local/bin/bun /usr/local/bin/bun

COPY --from=node:18.19-bookworm /usr/local/bin /usr/local/bin
COPY --from=node:18.19-bookworm /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN npm install --global tsx

RUN set -e \
    && printf '; priority=20\nextension=protobuf.so' > /etc/php/8.3/mods-available/protobuf.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/deskpro.ini \
    && printf '; priority=90\n; placeholder' > /etc/php/8.3/mods-available/deskpro-otel.ini \
    && phpenmod protobuf deskpro \
    && phpdismod phar \
    && rm /etc/php/8.3/fpm/pool.d/www.conf \
    && mv /etc/nginx/mime.types /tmp/mime.types \
    && rm -rf /etc/nginx \
    && mkdir -p /etc/nginx/conf.d \
    && chmod 0755 /etc/nginx /etc/nginx/conf.d \
    && mv /tmp/mime.types /etc/nginx

COPY etc /etc/
COPY usr/local/bin /usr/local/bin/
COPY usr/local/lib /usr/local/lib/
COPY usr/local/sbin /usr/local/sbin/
COPY usr/local/share/deskpro /usr/local/share/deskpro/

RUN set -e \
    # dp_app user is used when we run any app code (e.g. php-fpm, CLI tasks, etc) \
    && addgroup --gid 1083 dp_app \
    && adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1083 --gid 1083 dp_app \
    # vector user for logs \
    && addgroup --gid 1084 vector \
    && adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1084 --gid 1084 vector \
    # add vector to adm group so it can read logs \
    && usermod -a -G adm vector \
    # we run nginx as its own user \
    && addgroup --gid 1085 nginx \
    && adduser --system --shell /bin/false --no-create-home --disabled-password --uid 1085 --gid 1085 nginx \
    # initialize dirs and owners \
    && mkdir -p /var/log/nginx /var/log/php /var/log/deskpro /var/log/supervisor /var/lib/vector \
    && mkdir -p /srv/deskpro/INSTANCE_DATA/deskpro-config.d \
    && chown root:root /usr/local/bin/vector \
    && chown vector:adm /var/lib/vector \
    && chown nginx:adm /var/log/nginx \
    && chown dp_app:adm /var/log/php /var/log/deskpro \
    && chmod -R 0775 /var/log/php /var/log/deskpro \
    # set group sticky bit on these dirs so \
    # new logs get created with adm group (so vector can read them) \
    && chmod g+s /var/log/nginx /var/log/php /var/log/deskpro \
    # extract var names from our reference list \
    # (these lists are used from various helper scripts or entrypoint scripts) \
    && jq -r '.[] | select(.isPrivate|not) | .name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-public-var-list \
    && jq -r '.[] | select(.isPrivate) | .name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-private-var-list \
    && jq -r '.[] | select(.setEnv) | .name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-setenv-var-list \
    && jq -r '.[].name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-var-list \
    && chmod 644 /usr/local/share/deskpro/*

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
ENV LOGS_EXPORT_FILENAME "{{.container_name}}/{{.app}}/{{.chan}}.log"

# Log output format: logfmt or json
ENV LOGS_OUTPUT_FORMAT "logfmt"

# GID to use for exported log files. By default, logs will be owned by the vector group (GID 1084).
ENV LOGS_GID ""

ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
CMD ["web"]
