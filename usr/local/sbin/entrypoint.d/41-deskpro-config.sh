#!/bin/bash
#######################################################################
# This source handles writing the main deskpro config.php.
#
# The config file is a config 'entrypoint' that just includes all
# other config files.
#
# There's at least 1 main config file (typically deskpro-config.php)
# and then any extras that are in the deskpro-config.d directory.
#######################################################################

function deskpro_config_main() {
  {
    echo "<?php"
    echo "// DO NOT EDIT THIS FILE - IT IS AUTO-GENERATED"
    echo ""
    echo "require_once(\"/srv/deskpro/INSTANCE_DATA/$(basename "$DESKPRO_CONFIG_FILE" .tmpl)\");"

    for f in /srv/deskpro/INSTANCE_DATA/deskpro-config.d/*.php; do
      if [ ! -e "$f" ] || [ -d "$f" ]; then
        continue
      fi

      echo "require_once(\"$f\");"
    done
  } > /srv/deskpro/INSTANCE_DATA/config.php

  chown dp_app:dp_app "/srv/deskpro/INSTANCE_DATA/config.php"
  chmod 0644 "/srv/deskpro/INSTANCE_DATA/config.php"
}

deskpro_config_main
unset deskpro_config_main
