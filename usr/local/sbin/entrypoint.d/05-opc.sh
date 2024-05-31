#!/bin/bash
#######################################################################
# This source handles OPC related options / auto configuration,
# and backwards compat for older OPC releases.
#######################################################################

opc_main() {
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

  boot_log_message DEBUG "[opc] Setting LOGS_EXPORT_FILENAME pattern app.chan.log"
  export LOGS_EXPORT_FILENAME="{{.container_name}}-{{.app}}.{{.chan}}.log"

  boot_log_message DEBUG "[opc] Setting DESKPRO_API_BASE_URL_PRIVATE to use loopback if not set"
  if [ -z "$DESKPRO_API_BASE_URL_PRIVATE" ]; then
    export DESKPRO_API_BASE_URL_PRIVATE="http://127.0.0.1:80"
  fi

  boot_log_message DEBUG "[opc] Extract DB vars from config"
  if [ -f "$CUSTOM_MOUNT_BASEDIR/config/deskpro-config.php" ]; then
    eval "$(/usr/local/sbin/entrypoint.d/helpers/bc-extract-db-from-config.php)"
  fi

  boot_log_message DEBUG "[bc_opc_2_8] Linking /run/php-fpm/dp_default.sock -> /run/php_fpm_dp_default.sock"
  mkdir -p /run/php-fpm
  ln -sf /run/php_fpm_dp_default.sock /run/php-fpm/dp_default.sock

  for pool in "dp_broadcaster" "dp_default" "dp_gql" "dp_internal"; do
    if [ -e "/deskpro/config/${pool}.conf" ]; then
      boot_log_message DEBUG "[bc_opc_2_8] Copying /deskpro/config/${pool}.conf to /etc/php/8.3/fpm/pool.d/zz_${pool}.conf"

      # copy the config and perform in-place modifications to ensure that the config is valid
      cat "/deskpro/config/${pool}.conf" \
        | sed 's/^user = php$/user = dp_app/g' \
        | sed 's/^group = php$/group = dp_app/g' \
        | sed "s/^listen = \/run\/php-fpm\/${pool}.sock$/listen = \/run\/php_fpm_${pool}.sock/g" \
      > "/etc/php/8.3/fpm/pool.d/zz_${pool}.conf"
    fi
  done
}

opc_main
unset opc_main
