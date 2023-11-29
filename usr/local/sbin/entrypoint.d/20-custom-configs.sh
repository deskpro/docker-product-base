#!/bin/bash
#######################################################################
# This source handles copying custom config files into place within
# the container at the proper places.
#
# We COPY files because we want to avoid having to deal with permissions.
#######################################################################

custom_configs_main() {
  install_custom_config_dirs
  install_deskpro_config_raw_php
  install_deskpro_config_file
}

# Install custom config files from .d dirs
install_custom_config_dirs() {
  copy_custom_config_dir "$CUSTOM_MOUNT_BASEDIR/config/deskpro-config.d" "/srv/deskpro/INSTANCE_DATA/deskpro-config.d"
  copy_custom_config_dir "$CUSTOM_MOUNT_BASEDIR/config/nginx.d" "/etc/nginx/conf.d"
  copy_custom_config_dir "$CUSTOM_MOUNT_BASEDIR/config/vector.d" "/etc/vector/vector.d"
  copy_custom_config_dir "$CUSTOM_MOUNT_BASEDIR/config/php-fpm.d" "/etc/php/8.1/fpm/pool.d"
  copy_custom_config_dir "$CUSTOM_MOUNT_BASEDIR/config/php.d" "/etc/php/8.1/fpm/conf.d"
  copy_custom_config_dir "$CUSTOM_MOUNT_BASEDIR/config/php.d" "/etc/php/8.1/cli/conf.d"
}

# Install the "base" deskpro config file.
# This is /etc/templates/deskpro-config.php.tmpl by default
# but it can be changed via DESKPRO_CONFIG_FILE
install_deskpro_config_file() {
  if [ ! -f "$DESKPRO_CONFIG_FILE" ]; then
    boot_log_message ERROR "DESKPRO_CONFIG_FILE=$DESKPRO_CONFIG_FILE does not exist"
    exit 1
  fi

  local fname=""
  fname=$(basename "$DESKPRO_CONFIG_FILE")

  if [ "$fname" == "config.php" ] || [ "$fname" == "config.php.tmpl" ]; then
    # the config.php file is reserved
    # so we need to re-set it to a custom prefix
    fname="custom_$fname"
  fi

  cp "$DESKPRO_CONFIG_FILE" "/srv/deskpro/INSTANCE_DATA/$fname"
  chown root:root "/srv/deskpro/INSTANCE_DATA/$fname"
  chmod 0644 "/srv/deskpro/INSTANCE_DATA/$fname"
}

# Writes DESKPRO_CONFIG_RAW_PHP to a file in /srv/deskpro/INSTANCE_DATA/deskpro-config.d
install_deskpro_config_raw_php() {
  local DESKPRO_CONFIG_RAW_PHP=$(container-var DESKPRO_CONFIG_RAW_PHP)
  if [ -z "$DESKPRO_CONFIG_RAW_PHP" ]; then
    return 0
  fi

  boot_log_message INFO "Installing DESKPRO_CONFIG_RAW_PHP to /srv/deskpro/INSTANCE_DATA/deskpro-config.d/DESKPRO_CONFIG_RAW_PHP.php"
  printf '<?php\n%s\n' "$DESKPRO_CONFIG_RAW_PHP" > "/srv/deskpro/INSTANCE_DATA/deskpro-config.d/DESKPRO_CONFIG_RAW_PHP.php"
  chown root:root "/srv/deskpro/INSTANCE_DATA/$fname"
  chmod 0644 "/srv/deskpro/INSTANCE_DATA/$fname"
}

#######################################################################
# Copy files from a directory to another directory, and set permissions
# so they are owned by root.
#
# ARGUMENTS:
#  $1 - Custom config directory
#  $2 - Destination directory
#######################################################################
copy_custom_config_dir() {
  if [ ! -d "$1" ]; then
    return 0
  fi

  boot_log_message INFO "Copying custom config files from $1 -> $2"
  for f in "$1"/*; do
    if [ ! -e "$f" ] || [ -d "$f" ]; then
      continue
    fi
    tofile="$2/$(basename "$f")"
    cp "$f" "$tofile"
    chown root:root "$tofile"
    chmod 0644 "$tofile"
  done
}

custom_configs_main
unset custom_configs_main install_custom_config_dirs install_deskpro_config_raw_php install_deskpro_config_file copy_custom_config_dir
