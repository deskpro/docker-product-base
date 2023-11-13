# syntax=docker/dockerfile:1
FROM alpine:3.18
WORKDIR /srv/deskpro
USER root

ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so
ENV TZ=UTC

RUN <<EOT
    apk --update --no-cache add \
        bash \
        ca-certificates \
        coreutils \
        curl \
        fcgi \
        findutils \
        gnu-libiconv \
        iproute2 \
        iproute2-ss \
        jq \
        mariadb-client \
        mariadb-connector-c \
        nano \
        nginx \
        openssl \
        php81 \
        php81-common \
        php81-ctype \
        php81-curl \
        php81-dom \
        php81-fileinfo \
        php81-fpm \
        php81-gd \
        php81-iconv \
        php81-imap \
        php81-intl \
        php81-ldap \
        php81-mbstring \
        php81-mysqlnd \
        php81-opcache \
        php81-openssl \
        php81-pcntl \
        php81-pdo \
        php81-pdo_mysql \
        php81-pecl-protobuf \
        php81-phar \
        php81-posix \
        php81-session \
        php81-simplexml \
        php81-soap \
        php81-sockets \
        php81-sodium \
        php81-tokenizer \
        php81-xml \
        php81-xmlwriter \
        php81-zip \
        ripgrep \
        rsync \
        sudo \
        supervisor \
        tzdata

    apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community php81-pecl-opentelemetry

    cp /usr/share/zoneinfo/UTC /etc/localtime

    # removes python bytecode files (saves some disk space)
    find /usr/lib/python3.11 -type f -name '*.py[co]' -delete -o -type d -name __pycache__ -delete

    # Remove default configs because we will install our own
    rm -f /etc/php81/php.ini \
        /etc/php81/conf.d/opentelemetry.ini \
        /etc/php81/php-fpm.d/www.conf \
        /etc/nginx/nginx.conf \
        /etc/nginx/fastcgi_params \
        /etc/nginx/http.d/default.conf \
        /etc/nginx/scgi_params \
        /etc/nginx/uwsgi_params \
        /etc/nginx/fastcgi.conf \
        /etc/supervisord.conf
    rmdir /etc/nginx/modules
EOT

COPY --link --from=hairyhenderson/gomplate:v3.11.5 /gomplate /usr/local/bin/gomplate
COPY --link --from=composer:2.5.8 /usr/bin/composer /usr/local/bin/composer
COPY --link --from=timberio/vector:0.31.0-alpine /usr/local/bin/vector /usr/local/bin/vector

COPY --link etc /etc/
COPY --link usr/local/bin /usr/local/bin/
COPY --link usr/local/lib /usr/local/lib/
COPY --link usr/local/sbin /usr/local/sbin/
COPY --link usr/local/share/deskpro /usr/local/share/deskpro/

RUN <<EOT
    ln -s /etc/php81 /etc/php
    ln -s /usr/sbin/php-fpm81 /usr/sbin/php-fpm

    # dp_app user is used when we run any app code (e.g. php-fpm, CLI tasks, etc)
    addgroup -S -g 1083 dp_app
    adduser -S -D -H -s /bin/false -u 1083 -G dp_app dp_app

    # vector user for logs is added to adm group so it can read logs
    adduser -S -D -H -s /bin/false -u 1084 -G adm vector

    # initialize dirs and owners
    mkdir -p /var/log/nginx /var/log/php /var/log/deskpro /var/log/supervisor /var/lib/vector
    mkdir -p /srv/deskpro/INSTANCE_DATA/deskpro-config.d
    rm -rf /var/log/php81
    chown root:root /usr/local/bin/vector
    chown vector:adm /var/lib/vector
    chown nginx:adm /var/log/nginx
    chown dp_app:adm /var/log/php /var/log/deskpro
    chmod -R 0775 /var/log/php /var/log/deskpro

    # set group sticky bit on these dirs so
    # new logs get created with adm group (so vector can read them)
    chmod g+s /var/log/nginx /var/log/php /var/log/deskpro

    # extract var names from our reference list
    # (these lists are used from various helper scripts or entrypoint scripts)
    jq -r '.[] | select(.isPrivate|not) | .name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-public-var-list
    jq -r '.[] | select(.isPrivate) | .name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-private-var-list
    jq -r '.[].name' /usr/local/share/deskpro/container-var-reference.json > /usr/local/share/deskpro/container-var-list
    chmod 644 /usr/local/share/deskpro/*
EOT

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
ENV DESKPRO_CONFIG_FILE "/etc/templates/deskpro-config.php.tmpl"

# Log level for entrypoint scripts that controls which logs are printed to stderr
ENV BOOT_LOG_LEVEL "INFO"
ENV BOOT_LOG_LEVEL_EXEC "WARNING"

# If this is set, then logs will be written out to this directory
# (if CUSTOM_MOUNT_BASEDIR/logs exists, then this will be set to that dir if not already set)
ENV LOGS_EXPORT_DIR ""

# The filename to use when writing logs to LOGS_EXPORT_DIR
ENV LOGS_EXPORT_FILENAME "{{.container_name}}/{{.app}}/{{.chan}}.log"

# Log output format: logfmt or json
ENV LOGS_OUTPUT_FORMAT "logfmt"

ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
CMD ["web"]
