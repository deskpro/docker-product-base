#!/bin/bash
#######################################################################
# This source just sets up basic environment
#######################################################################

export PYTHONDONTWRITEBYTECODE=1

# If there is no root, we will create it now (e.g. base image without Deskpro on it yet)
if [ ! -d /srv/deskpro/serve/www ]; then
  boot_log_message ERROR "Source files not detected."

  mkdir -p /srv/deskpro/serve/www
  echo "Missing source files." > /srv/deskpro/serve/www/index.php
fi

if [ ! -d "/run/container-config" ]; then
  mkdir /run/container-config
  chmod 1711 /run/container-config
fi

# vector uses a checksum of the first line to efficiently
# determine when logs are rotated.
# when we rotate logs we add a line with this magic const
# so we can subsequently ignore it in processing.
export VECTOR_MARKER="E48C59D7-3E1C-4BAF-B6BC-07DC4D99699F-315F22F7-5F3C-47BB-92E1-67EFE58EBFB0"

# init log files - helps vector checkpoint better
for f in \
  "/var/log/nginx/access.log" \
  "/var/log/nginx/error.log" \
  "/var/log/php/error.log" \
  "/var/log/php/fpm_error.log" \
  "/var/log/supervisor/tasks.log" \
  "/var/log/supervisor/email_collect.log" \
  "/var/log/supervisor/email_process.log" \
  "/var/log/supervisor/nginx.log" \
  "/var/log/supervisor/php_fpm.log" \
  "/var/log/supervisor/tasks.log"
do
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Log file started: $f -- ${VECTOR_MARKER}" > "$f"
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Log file started: $f.1 -- ${VECTOR_MARKER}" > "$f.1"
done

chown -R nginx:adm /var/log/nginx/*.log
chown -R dp_app:adm /var/log/php/*.log

touch /var/log/vector.log
chown vector:adm /var/log/vector.log

# Ensure cron status file exists
echo '{ "lastStart": null, "lastFinish": null, "lastError": null, "lastSuccess": null }' > /run/deskpro-cron-status.json
chown root:dp_app /run/deskpro-cron-status.json
chmod 774 /run/deskpro-cron-status.json
