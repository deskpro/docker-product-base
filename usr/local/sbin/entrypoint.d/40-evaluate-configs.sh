#!/bin/bash
#######################################################################
# This source goes through config file dirs and evaluates any .tmpl
# files as templates. Files are output to the same directory with the
# same name but without the .tmpl extension.
#######################################################################

function evaluate_configs_main() {

  # gomplate --input-dir is recursive so we only want to specify base dirs here
  declare -a tplDirs=(
    "/srv/deskpro/INSTANCE_DATA"
    "/etc/php/8.3"
    "/etc/vector/vector.d"
    "/etc/nginx"
    "/etc/supervisor"
    "/etc/vector"
  )

  set +o errexit

  for i in "${tplDirs[@]}"; do
    i=$(realpath "$i")
    if [ -d "$i" ]; then
      /usr/local/bin/gomplate --include="*.tmpl" --input-dir="$i" --output-map="$i/{{ .in | strings.ReplaceAll \".tmpl\" \"\" }}"

      # if it failed then try again
      if [ $? -ne 0 ]; then
        /usr/local/bin/gomplate --include="*.tmpl" --input-dir="$i" --output-map="$i/{{ .in | strings.ReplaceAll \".tmpl\" \"\" }}"

        # if it still failed then raise error
        if [ $? -ne 0 ]; then
          boot_log_message ERROR "[evaluate_configs_main] Failed to evaluate templates in $i"
          exit 1
        fi
      fi
    fi
  done

  /usr/local/bin/gomplate -f /usr/local/share/deskpro/templates/svc-messenger-api.env.tmpl -o /srv/deskpro/services/messenger-api/.env
  /usr/local/bin/gomplate -f /usr/local/share/deskpro/templates/svc-deskpro-messenger.env.tmpl -o /srv/deskpro/packages/deskpro-messenger/.env

  set -o errexit
}

evaluate_configs_main
unset evaluate_configs_main
