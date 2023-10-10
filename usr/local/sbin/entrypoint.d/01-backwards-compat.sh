#!/bin/bash
#######################################################################
# This source handles backwards compatibility with old container env vars
# or file customization options.
#
# Older options are "mapped" into newer options. Old options should
# then be unset so the rest of the entrypoint scripts don't need to
# "know" they exist at all.
#######################################################################

backwards_compat_main() {
  bc_run_mode
  bc_var_renames
  bc_pool_config
  bc_custom_php_config
  bc_deskpro_custom_config
  bc_deskpro_full_config_override
}

# The old container was run without a command or with the command set to the 'cron' script.
# We need to turn those values into the new 'run mode' values.
bc_run_mode() {
  if [ -z "$DOCKER_CMD" ]; then
    boot_log_message DEBUG "[backwards-compat] No DOCKER_CMD specified, defaulting to web"
    export DOCKER_CMD="web"
  elif [ "$DOCKER_CMD" == "/usr/local/bin/start-cron.sh" ]; then
    boot_log_message DEBUG "[backwards-compat] DOCKER_CMD was set to start-cron.sh, correcting to DOCKER_CMD=tasks"
    export DOCKER_CMD="tasks"
  fi
}

bc_var_renames() {
  # The old container used env vars 'DESKPRO_DB_REPLICA_' instead of 'DESKPRO_DB_READ_'
  bc_rename_container_var DESKPRO_DB_REPLICA_HOST DESKPRO_DB_READ_HOST
  bc_rename_container_var DESKPRO_DB_REPLICA_PORT DESKPRO_DB_READ_PORT

  bc_rename_container_var DESKPRO_APIURL_BASEURL_PRIVATE DESKPRO_API_BASE_URL_PRIVATE
  bc_rename_container_var DESKPRO_USE_TEST_SSL_CERT HTTP_USE_TESTING_CERTIFICATE
}

bc_pool_config() {
  if [ -n "$PHP_FPM_DP_DEFAULT_MAX_CHILDREN" ]; then
    (( result=(PHP_FPM_DP_DEFAULT_MAX_CHILDREN+5-1)/5 ))
    export PHP_FPM_DP_DEFAULT_NUM_POOLS="$result"
    boot_log_message DEBUG "[backwards-compat] PHP_FPM_DP_DEFAULT_NUM_POOLS=$PHP_FPM_DP_DEFAULT_NUM_POOLS (from PHP_FPM_DP_DEFAULT_MAX_CHILDREN=$PHP_FPM_DP_DEFAULT_MAX_CHILDREN)"
    unset PHP_FPM_DP_DEFAULT_MAX_CHILDREN
  fi

  if [ -n "$PHP_FPM_DP_GQL_MAX_CHILDREN" ]; then
    (( result=(PHP_FPM_DP_GQL_MAX_CHILDREN+5-1)/5 ))
    export PHP_FPM_DP_AGENT_NUM_POOLS="$result"
    boot_log_message DEBUG "[backwards-compat] PHP_FPM_DP_AGENT_NUM_POOLS=$PHP_FPM_DP_AGENT_NUM_POOLS (from PHP_FPM_DP_GQL_MAX_CHILDREN=$PHP_FPM_DP_GQL_MAX_CHILDREN)"
    unset PHP_FPM_DP_GQL_MAX_CHILDREN
  fi

  bc_rename_container_var PHP_FPM_DP_GQL_OVERRIDES PHP_FPM_DP_AGENT_OVERRIDES
}

# Old container php.ini and php-fpm.conf config overrides
bc_custom_php_config() {
  bc_rename_container_var CUSTOM_PHP_INI_APPEND PHP_INI_OVERRIDES prepend
  bc_rename_container_var FPM_APPEND PHP_FPM_POOL_OVERRIDES prepend
  bc_rename_container_var FPM_APPEND_DP_DEFAULT PHP_FPM_DP_DEFAULT_OVERRIDES prepend
  bc_rename_container_var FPM_APPEND_DP_BROADCASTER PHP_FPM_DP_BROADCASTER_OVERRIDES prepend
  bc_rename_container_var FPM_APPEND_DP_GQL PHP_FPM_DP_BROADCASTER_OVERRIDES prepend
  bc_rename_container_var FPM_APPEND_DP_INTERNAL PHP_FPM_DP_INTERNAL_OVERRIDES prepend
}

# Old container would check for a file named config.custom.php
# This is the only file that will be _linked_ instead of copied
# because sometimes it's useful to be able to test things rapidly
# without restarting the container.
bc_deskpro_custom_config() {
  local custom_file="$CUSTOM_MOUNT_BASEDIR/config/config.custom.php"

  local dest_file_name="zzzz-config.custom.php"
  local dest_file_path="/srv/deskpro/INSTANCE_DATA/deskpro-config.d/$dest_file_name"

  if [ -e "$custom_file" ]; then
    boot_log_message INFO "[backwards-compat] Linking $custom_file to deskpro-config.d/$dest_file_name"
    ln -sf "$custom_file" "$dest_file_path"

    # attempt to chown+chmod the file to make sure its not writable when it should not be
    # (but ignore any errors in doing so)
    chown root:root "$dest_file_path" >/dev/null 2>&1 || true
    chmod 0644 "$dest_file_path" >/dev/null 2>&1 || true
  fi
}

# Old container would check for a file named deskpro-config.php and use it
# as the base config file. New container does this by the DESKPRO_CONFIG_FILE variable instead.
bc_deskpro_full_config_override() {
  if [ "$DESKPRO_CONFIG_FILE" != "/etc/templates/deskpro-config.php.tmpl" ]; then
    # dont do bc check if DESKPRO_CONFIG_FILE is already non-default
    # because it means its aleady been overriden explicitly
    return
  fi

  local custom_file="$CUSTOM_MOUNT_BASEDIR/config/deskpro-config.php"

  if [ -e "$custom_file" ]; then
    boot_log_message DEBUG "[backwards-compat] Using full Deskpro config file override DESKPRO_CONFIG_FILE=$custom_file"
    export DESKPRO_CONFIG_FILE="$custom_file"
  fi
}

#######################################################################
# Renames an env var from the old name to the new name, then unsets
# the old name.
#
# ARGUMENTS:
#   $1 - The old env var name
#   $2 - The new env var name
#   $3 - (Optional) Set to 'prepend' to prepend the old value to the new if both exist.
#######################################################################
bc_rename_container_var() {
  local old_name="$1"
  local new_name="$2"
  local do_combine="${3:-}"

  if [ -z "${!old_name}" ]; then
    # The old env var was not set, so nothing to do
    return
  fi

  # We already have a new new, so we can just unset the old one
  if [ -n "${!new_name}" ]; then
    if [ "${!old_name}" != "${!new_name}" ]; then
      if [ "$do_combine" == "prepend" ]; then
        boot_log_message WARNING "[backwards-compat] The variable '$new_name' and the legacy variable '$old_name' are both set but they contain different values. The legacy value will be PREPENDED to the new value. You should remove the use of the legacy variable."
        local new_value=""
        new_value="$(printf "%s\\n%s" "${!old_name}" "${!new_name}")"
        declare -gx "$new_name"="$new_value"
      else
        boot_log_message ERROR "[backwards-compat] The variable '$new_name' and the legacy variable '$old_name' are both set but they contain different values. The legacy value will be UNUSED. You should remove the use of the legacy variable."
      fi
    fi

    unset "$old_name"
    return
  fi

  boot_log_message INFO "[backwards-compat] Rename $old_name -> $new_name"
  declare -gx "$new_name"="${!old_name}"
  unset "$old_name"
}

backwards_compat_main
unset backwards_compat_main bc_run_mode bc_var_renames bc_pool_config bc_custom_php_config bc_deskpro_custom_config bc_deskpro_full_config_override bc_rename_container_var
