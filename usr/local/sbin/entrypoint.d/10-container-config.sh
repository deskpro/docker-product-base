#!/bin/bash
#######################################################################
# This source moves values from env vars to files in /run/container-config.
#
# E.g. a variable DESKPRO_DB_PASS:
# 1) Value is written to /run/container-config/DESKPRO_DB_PASS
# 2) DESKPRO_DB_PASS is unset
# 3) DESKPRO_DB_PASS_FILE is set to /run/container-config/DESKPRO_DB_PASS
#
# This "hides" real values from the environment as a basic security measure.
# When config files are evaluated, gomplate handles the _FILE suffix and
# will "just work".
#
# We also handle _B64 and _ESC suffixes for base64 and escape decoding here.
# E.g. a variable FOO_BAR_B64 will be decoded and then set to the FOO_BAR value.
#######################################################################

container_config_main() {
  local base_varname;

  # Move env vars to /run/container-config
  while read -r base_varname; do
    if init_container_var_value "$base_varname"; then
      # if a var is actually set, then we need to
      # save a _FILE into the env so our tools know where to look
      declare -gx "${base_varname}_FILE"="/run/container-config/$base_varname"
    fi

    # unset from from env
    # - only N_FILE will remain or if the original var is in the env
    # then that is not unset until 90-clean.sh (as a small micro-opt for gomplate)
    unset "${base_varname}_B64" "${base_varname}_B64_FILE" "${base_varname}_ESC" "${base_varname}_ESC_FILE"
  done < /usr/local/share/deskpro/container-public-var-list
}


#######################################################################
# init an env var from the various places it may be defined and
# decodes it if necessary.
#
# ARGUMENTS:
#  $1 - The base variable name
#
# RETURN:
#  0 - Value was set
#  1 - No variable was set
#######################################################################
init_container_var_value() {
  local base_varname="$1"
  local target_file="/run/container-config/$base_varname"

  for suf in "" "_B64" "_ESC"; do
    local varname="${base_varname}${suf}"
    local filevar="${varname}_FILE"
    local filename="${!filevar}"
    local valuefrom=""

    if [ -n "$filename" ] && [ -f "$filename" ]; then
      valuefrom="file"
      boot_log_message TRACE "Variable \$$base_varname from env var file \$$filevar: $filename"
    elif [ -v "$varname" ]; then
      valuefrom="env"
      boot_log_message TRACE "Variable \$$base_varname from env var \$$varname"
    elif [ -f "/run/secrets/$varname" ]; then
      valuefrom="file"
      filename="/run/secrets/$varname"
      boot_log_message TRACE "Variable \$$base_varname from file: $filename"
    else
      # no value found
      continue
    fi

    case "$suf" in
      _B64)
        if [ "$valuefrom" == "file" ]; then
          base64 -d -i "$filename" > "$target_file"
        else
          base64 -d -i <<< "${!varname}" > "$target_file"
        fi
        chmod 660 "$target_file"
        return 0
        ;;

      _ESC)
        if [ "$valuefrom" == "file" ]; then
          printf "%b" "$(cat "$filename")" > "$target_file"
        else
          printf "%b" "${!varname}" > "$target_file"
        fi
        chmod 660 "$target_file"
        return 0
        ;;

      *)
        if [ "$valuefrom" == "file" ]; then
          ln -sf "$filename" "$target_file"
        else
          # already set in env, write it to file
          printf '%s' "${!varname}" > "$target_file"
          chmod 660 "$target_file"
        fi
        return 0
        ;;
    esac
  done

  return 1
}

container_config_main
unset container_config_main init_container_var_value
