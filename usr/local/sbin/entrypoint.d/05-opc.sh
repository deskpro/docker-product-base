#!/bin/bash
#######################################################################
# This source handles OPC related options / auto configuration,
# and backwards compat for older OPC releases.
#######################################################################

opc_main() {
  # if this is OPC and we dont have a config version
  # then guess that it's 2.8.0, though it could be lower
  if [ -n "$DESKPRO_OPC_WEBGUI_BASEURL" ] && [ -z "$OPC_VERSION" ]; then
    export OPC_VERSION=2.8.0
    boot_log_message DEBUG "[opc] Detected old OPC version, assuming 2.8.0"
  fi

  # These routines dont apply if not opc
  if [ -z "$OPC_VERSION" ]; then
    boot_log_message TRACE "[opc] Not running in OPC"
    return
  fi

  boot_log_message INFO "[opc] Detected OPC version $OPC_VERSION"

  # OPC uses nginx on the host as a reverse proxy
  boot_log_message INFO "[opc] Enabling X-Forwarded- headers"
  export HTTP_USER_REAL_IP_HEADER="X-Forwarded-For"
  export HTTP_USER_REAL_PROTO_HEADER="X-Forwarded-Proto"
  export HTTP_USER_REAL_HOST_HEADER="X-Forwarded-Host"
  export HTTP_USER_REAL_PORT_HEADER="X-Forwarded-Port"

  boot_log_message INFO "[opc] Installing /srv/deskpro/INSTANCE_DATA/deskpro-config.d/01-deskpro-opc.php"
  cp /usr/local/sbin/entrypoint.d/helpers/01-deskpro-opc.php.tmpl /srv/deskpro/INSTANCE_DATA/deskpro-config.d/01-deskpro-opc.php.tmpl

  if php -r "exit(version_compare('$OPC_VERSION', '2.9', '<') ? 0 : 1);"; then
    bc_opc_2_8
  fi
}

bc_opc_2_8() {
  boot_log_message TRACE "[bc_opc_2_8] Running backwards compat for OPC <=2.8.0"

  # OPC used /deskpro/var/logs instead of /deskpro/logs
  if [ -z "$LOGS_EXPORT_DIR" ] && [ -d "/deskpro/var/logs" ]; then
    boot_log_message DEBUG "[bc_opc_2_8] Setting LOGS_EXPORT_DIR=/deskpro/var/logs"
    export LOGS_EXPORT_DIR="/deskpro/var/logs"

    # This is necessary because the host has logrotate but only
    # on *.log within the directory (i.e. not nested)
    boot_log_message DEBUG "[bc_opc_2_8] Setting LOGS_EXPORT_FILENAME pattern app.chan.log"
    export LOGS_EXPORT_FILENAME="{{.container_name}}-{{.app}}.{{.chan}}.log"
  fi

  # Fix url env var
  export DESKPRO_API_BASE_URL_PRIVATE="${DESKPRO_API_BASE_URL:-http://127.0.0.1:80}"

  # these dont apply anymore so just unset them
  unset NGINX_ACCESS_LOG_PATH
  unset NGINX_ERROR_LOG_PATH
  unset NGINX_CLIENT_MAX_BODY_SIZE
  unset PHP_POST_MAX_SIZE
  unset PHP_UPLOAD_MAX_FILESIZE
  unset PHP_ERROR_LOG
  unset CRON_LOG_FILE

  if [ -n "$CRON_STATUS_FILE" ]; then
    printf '%s' "${CRON_STATUS_FILE}" > "/run/container-config/CRON_STATUS_FILEPATH"
    export CRON_STATUS_FILEPATH_FILE="/run/container-config/CRON_STATUS_FILEPATH"
    unset CRON_STATUS_FILE
  fi

  # extract DB vars from the config so mysql-read and mysql-primary utils work
  if [ -f "$CUSTOM_MOUNT_BASEDIR/config/deskpro-config.php" ]; then
    eval "$(/usr/local/sbin/entrypoint.d/helpers/bc-extract-db-from-config.php)"
  fi

  boot_log_message DEBUG "[bc_opc_2_8] Linking /run/php-fpm/dp_default.sock -> /run/php_fpm_dp_default.sock"
  mkdir /run/php-fpm
  ln -sf /run/php_fpm_dp_default.sock /run/php-fpm/dp_default.sock

  for pool in "dp_broadcaster" "dp_default" "dp_gql" "dp_internal"; do
    if [ -e "/deskpro/config/${pool}.conf" ]; then
      boot_log_message DEBUG "[bc_opc_2_8] Copying /deskpro/config/${pool}.conf to /etc/php/8.1/fpm/pool.d/zz_${pool}.conf"
      cp -f "/deskpro/config/${pool}.conf" "/etc/php/8.1/fpm/pool.d/zz_${pool}.conf"
    fi
  done
}

opc_main
unset opc_main bc_opc_2_8
