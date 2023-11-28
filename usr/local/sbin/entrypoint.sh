#!/bin/bash
#######################################################################
# The entrypoint script for the docker image. This script sets up the
# runtime environment and then executes the desired "run mode".
#######################################################################

set -o errexit
set -o pipefail

# The command passed to docker run. This first argument is what we refer to
# as the "run mode and is used to determine what to actually run.
export DOCKER_CMD="$1"
export DOCKER_CMD_ARGS=("${@:2}")

# After entrypoint scripts are run, this should be populated with one of
# the exec modes (exec, bash, supervisord) with the appropriate arguments.
export DOCKER_EXEC=""
export DOCKER_EXEC_ARGS=()

# Main logging format: logfmt or json
export LOGS_OUTPUT_FORMAT="${LOGS_OUTPUT_FORMAT:-logfmt}"

# If this is set, then logs get output to this directory instead of stdout
export LOGS_EXPORT_DIR="${LOGS_EXPORT_DIR:-}"

# The log level to output to stdout during this entrypoint script
# One of TRACE, DEBUG, INFO, WARNING, ERROR
export BOOT_LOG_LEVEL="${BOOT_LOG_LEVEL:-INFO}"
export BOOT_LOG_LEVEL="${BOOT_LOG_LEVEL^^}"

# Log level used for exec or bash modes. This will typically be
# higher than BOOT_LOG_LEVEL so that we don't spam the users terminal
# when they are running exec or bash.
export BOOT_LOG_LEVEL_EXEC="${BOOT_LOG_LEVEL_EXEC:-WARNING}"

# A name used in logs
export CONTAINER_NAME="${CONTAINER_NAME:-}"

main() {
  # remove sentinel files that may be set from previous boots
  # (normally set in container-ready.sh - we want to remove them here, early, because they are used in healthcheck)
  rm -f /run/container-ready /run/container-running-installer /run/container-running-migrations

  # move an old boot log if it exists (e.g. from a previous boot)
  if [ -f /var/log/docker-boot.log ]; then
    cat /var/log/docker-boot.log >> "/var/log/docker-boot.full.log"
    rm /var/log/docker-boot.log
  fi

  if [ -z "$CONTAINER_NAME" ]; then
    # use the ECS task ID if that's available
    if [ -n "$ECS_CONTAINER_METADATA_URI_V4" ]; then
      export CONTAINER_NAME="$(curl -s "$ECS_CONTAINER_METADATA_URI_V4/task" | jq -r '.TaskARN | split("/") | last')"
    else
      export CONTAINER_NAME="$(hostname)"
    fi
  fi

  boot_log_message TRACE "--- STARTING DESKPRO CONTAINER ---"

  # If LOGS_EXPORT_DIR not explicitly set
  # but there is a mounted logs dir at the standard location
  # then we can enable export to that dir automatically
  if [ -z "$LOGS_EXPORT_DIR" ]; then
    if [ -d "$CUSTOM_MOUNT_BASEDIR/logs" ]; then
      export LOGS_EXPORT_DIR="$CUSTOM_MOUNT_BASEDIR/logs"
      boot_log_message INFO "Setting LOGS_EXPORT_DIR to mounted logs directory"
    fi
  fi

  # special 'false' value to explicitly disable log shipping
  # (e.g. if logs dir is mounted as per above, you may want to disable it explicitly)
  if [ "$LOGS_EXPORT_DIR" == "false" ]; then
    export LOGS_EXPORT_DIR=""
  fi

  # log to file when running exec/bash so the users terminal isn't spammed with output
  if [ "$DOCKER_CMD" == "exec" ] || [ "$DOCKER_CMD" == "bash" ]; then
    if [ "$BOOT_LOG_LEVEL_EXEC" != "$BOOT_LOG_LEVEL" ]; then
      export BOOT_LOG_LEVEL="$BOOT_LOG_LEVEL_EXEC"
      boot_log_message TRACE "Setting BOOT_LOG_LEVEL to $BOOT_LOG_LEVEL_EXEC (from BOOT_LOG_LEVEL_EXEC) for exec/bash modes"
      unset BOOT_LOG_LEVEL_EXEC
    fi
    if [ -z "$LOGS_EXPORT_DIR" ]; then
      export LOGS_EXPORT_DIR=/var/log/docker-logs
    fi
  fi

  if [ -n "$LOGS_EXPORT_DIR" ]; then
    if [ ! -d "$LOGS_EXPORT_DIR" ]; then
      mkdir -p "$LOGS_EXPORT_DIR"
      chown root:adm /var/log/docker-logs
      chmod 0770 /var/log/docker-logs
      chmod g+s /var/log/docker-logs
    fi

    # some messages may already be logged, so copy to the exported file
    cat /var/log/docker-boot.log >> "$LOGS_EXPORT_DIR/docker-boot.log"
    chown root:adm "$LOGS_EXPORT_DIR/docker-boot.log"
  fi

  boot_log_message TRACE "Docker command: $DOCKER_CMD ${DOCKER_CMD_ARGS[*]}"

  if [ "$LOGS_OUTPUT_FORMAT" != "logfmt" ] && [ "$LOGS_OUTPUT_FORMAT" != "json" ]; then
    export LOGS_OUTPUT_FORMAT=logfmt
    boot_log_message ERROR "Unknown LOGS_OUTPUT_FORMAT: $LOGS_OUTPUT_FORMAT. Expected logfmt or json."
  fi

  run_entrypoint_script_dir "/usr/local/sbin/entrypoint.d"
  run_entrypoint_script_dir "/deskpro/entrypoint.d"
  unset run_entrypoint_script_dir

  clean_env
  unset clean_env

  boot_log_message TRACE "DOCKER_EXEC=$DOCKER_EXEC"

  # copy to local vars so we can unset the global ones
  local l_docker_exec="$DOCKER_EXEC"
  local l_exec_args=("${DOCKER_EXEC_ARGS[@]}")
  unset DOCKER_EXEC DOCKER_EXEC_ARGS DOCKER_CMD DOCKER_CMD_ARGS

  # store the fact that we've booted once (can be used to check if we're rebooting)
  date -u +"%Y-%m-%dT%H:%M:%SZ" >> /run/container-booted
  chmod 0644 /run/container-booted

  case "$l_docker_exec" in
    exec)
      boot_log_message INFO "Starting services"
      /usr/bin/supervisord --silent --configuration=/etc/supervisor/supervisord.conf

      boot_log_message INFO "Waiting for is-ready"
      is-ready --wait

      boot_log_message INFO "[run] Running: ${l_exec_args[*]}"
      set +o errexit
      command "${l_exec_args[@]}"
      ret=$?
      set -o errexit
      boot_log_message INFO "Command exited with status: $ret"

      # graceful shutdown of supervisord
      boot_log_message TRACE "Stopping services"
      supervisorctl stop all > /dev/null
      kill -s SIGTERM "$(cat /run/supervisord.pid)"

      boot_log_message TRACE "Done all - exiting"
      exit "$ret"
      ;;
    bash)
      boot_log_message INFO "Starting services"
      /usr/bin/supervisord --silent --configuration=/etc/supervisor/supervisord.conf

      boot_log_message INFO "Waiting for is-ready"
      is-ready --wait

      boot_log_message INFO "[bash] Starting"
      set +o errexit
      /bin/bash -i
      ret=$?
      set -o errexit
      boot_log_message INFO "Bash exited with status: $ret"

      # graceful shutdown of supervisord
      boot_log_message TRACE "Stopping services"
      supervisorctl stop all > /dev/null
      kill -s SIGTERM "$(cat /run/supervisord.pid)"

      boot_log_message TRACE "Done all - exiting"
      exit "$ret"
      ;;
    supervisord)
      boot_log_message INFO "Starting services"
      if [ -n "$LOGS_EXPORT_DIR" ]; then
        boot_log_message INFO "NOTE: Logs are being written to disk (LOGS_EXPORT_DIR=$LOGS_EXPORT_DIR). You will not see any more output here on stdout unless there is a low-level error."
      fi
      exec /usr/bin/supervisord --silent --nodaemon --configuration=/etc/supervisor/supervisord.conf
      ;;
    *)
      boot_log_message ERROR "Unknown DOCKER_EXEC=$l_docker_exec"
      exit 2
      ;;
  esac
}

#######################################################################
# Runs .sh scripts in a directory and log basic timing information.
#
# ARGUMENTS:
#   $1 - The directory containing the scripts
#######################################################################
run_entrypoint_script_dir() {
  local dirpath="$1"
  local time1=""
  local time2=""
  local time_diff=""

  if [ ! -d "$dirpath" ]; then
    return
  fi

  for source_file in "$dirpath"/*.sh; do
    if [ ! -e "$source_file" ] || [ -d "$source_file" ]; then
      continue
    fi

    boot_log_message DEBUG "Running: $source_file"

    time1=$(date +%s.%N)
    # shellcheck disable=SC1090
    . "$source_file"
    time2=$(date +%s.%N)
    time_diff=$(echo "$time2 - $time1" | bc -l)
    boot_log_message TRACE "$(basename "$source_file") finished in $time_diff seconds"
  done
}

#######################################################################
# This cleans up the env by unsetting config variables
#######################################################################
clean_env() {
  if [ "$DISABLE_CLEAN_VARS" == "true" ]; then
    boot_log_message INFO "DISABLE_CLEAN_VARS=true - leaving env vars"
    return
  fi

  local varname;

  # user vars and options
  while read -r varname; do
    unset "${varname}" "${varname}_FILE"
  done < /usr/local/share/deskpro/container-public-var-list

  # private vars - move them into files in case we need to debug them
  while read -r varname; do
    if [ -v "$varname" ]; then
      printf '%s' "${!varname}" > "/run/container-config/$varname"
      unset "${varname}"
    fi
  done < /usr/local/share/deskpro/container-private-var-list

  # setenv vars - these are vars that must stay in the env as actual env vars
  while read -r varname; do
    local value=$(container-var "$varname")
    if [ -z "$value" ]; then
      declare -gx "${varname}"="$value"
    fi
  done < /usr/local/share/deskpro/container-setenv-var-list
}

#######################################################################
# Logs a message to /var/log/docker-boot.log and may also output to
# to stderr depending on the value of BOOT_LOG_LEVEL.
#
# ARGUMENTS:
#  $1 - The log level (TRACE, DEBUG, INFO, WARNING, ERROR)
#  $2 - The log message
#######################################################################
boot_log_message() {
  declare -A levels=([TRACE]=0 [DEBUG]=1 [INFO]=2 [WARNING]=3 [ERROR]=4)
  local lvl="${1^^}"
  local logline=""

  if [ "$LOGS_OUTPUT_FORMAT" == "logfmt" ]; then
    logline="ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ") app=entrypoint lvl=$lvl msg=$(echo -n "$2" | jq -Rsa .) container_name=$CONTAINER_NAME"
  else
    logline="{\"ts\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"app\":\"entrypoint\",\"lvl\":\"$lvl\",\"msg\":$(echo -n "$2" | jq -Rsa .),\"container_name\":\"$CONTAINER_NAME\"}"
  fi

  echo "$logline" >> /var/log/docker-boot.log

  if [ -n "$LOGS_EXPORT_DIR" ]; then
    if [ ! -f "$LOGS_EXPORT_DIR/docker-boot.log" ]; then
      touch "$LOGS_EXPORT_DIR/docker-boot.log"
      # make sure its not readable by anyone else but root
      chmod 0600 "$LOGS_EXPORT_DIR/docker-boot.log" || true
    fi
    echo "$logline" >> "$LOGS_EXPORT_DIR/docker-boot.log"
  fi

  [[ ${levels[$lvl]} ]] || return 0
  (( ${levels[$lvl]} < ${levels[$BOOT_LOG_LEVEL]} )) && return 0

  echo "$logline" >&2
}

main
