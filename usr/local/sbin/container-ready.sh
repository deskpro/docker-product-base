#!/bin/bash
#######################################################################
# This runs as a supervisor task after boot to run background
# app tasks to initialize the app. E.g. auto-install and auto-migrations
# are run from here.
#######################################################################

set -o pipefail

main() {
  log_message TRACE "Running container-ready.sh"
  cd /srv/deskpro

  services_running_ready

  # If we're running nginx, then check that nginx/fpm is actually running
  if [ "$(container-var SVC_NGINX_ENABLED)" == "true" ]; then
    log_message TRACE "[healthcheck:http] Waiting for http status endpoints to respond"
    (/usr/local/bin/healthcheck --wait --only --test-http 2>&1) | while IFS= read -r line; do log_message TRACE "[healthcheck:http] $line"; done
  fi

  log_message INFO "Container ready"
  date -u +"%Y-%m-%dT%H:%M:%SZ" > /run/container-ready
  chmod 0644 /run/container-ready

  # installer & migrations are run after setting container to ready
  # because the container is considered healthy while these are running
  # (see usr/loca/bin/healtcheck)
  # This is to avoid the container being marked as unhealthy and being killed.
  auto_run_tools

  log_message TRACE "container-ready.sh tasks done"
}

services_running_ready() {
    log_message TRACE "[services_running_ready] Waiting for services to leave STARTING state"
    while ! services_running; do
        log_message TRACE "[services_running_ready] Waiting ..."
        sleep 1
    done
    log_message TRACE "[services_running_ready] Ready"
}

services_running() {
  local status=$(supervisorctl status)
  if [[ $status == *"STARTING"* ]] || [[ $status == *"BACKOFF"* ]] || [[ $status == *"FATAL"* ]]; then
    return 1
  else
    return 0
  fi
}

#######################################################################
# Auto-run installer or migrations if needed
#######################################################################

auto_run_tools() {
  # unset flags that might've been set on a previous boot
  remove_sentinel_runfile installer
  remove_sentinel_runfile migrations

  AUTO_RUN_INSTALLER=$(container-var --default 0 AUTO_RUN_INSTALLER)
  AUTO_RUN_MIGRATIONS=$(container-var --default 0 AUTO_RUN_MIGRATIONS)
  log_message TRACE "AUTO_RUN_INSTALLER=$AUTO_RUN_INSTALLER, AUTO_RUN_MIGRATIONS=$AUTO_RUN_MIGRATIONS"

  if [ "$AUTO_RUN_INSTALLER" == "true" ] || [ "$AUTO_RUN_MIGRATIONS" == "true" ]; then
    log_message INFO "Waiting for DB to become ready"

    # wait for DB to come up (e.g. to handle a brand new docker-compose up where MySQL is being initialized)
    run_app_cmd php tools/fixtures/artisan test:wait-db --timeout 30
    status=$?

    if [ $status -ne 0 ]; then
      log_message ERROR "Could not connect to database for 30 seconds"
      exit 1
    fi

    # then check status of the db to see if we need to run migrations or installer
    run_app_cmd php tools/migrations/artisan migrations:status --errorOnPending
    status=$?

    case "$status" in
      0)
        log_message TRACE "DB is up to date"
        ;;

      # StatusCommand::EXIT_EMPTY_DB
      2)
        log_message WARNING "DB is empty - installer needs to run"
        if [ "$AUTO_RUN_INSTALLER" == "true" ]; then
          run_installer
        fi
        ;;

      # StatusCommand::EXIT_NOT_DESKPRO_DB
      3)
        log_message ERROR "DB is not empty but does not look like Deskpro"
        exit 1
        ;;

      # StatusCommand::EXIT_PENDING_INSTALL
      11)
        log_message WARNING "DB schema exists but no fixture data installed. Will bring up container as normal (assuming install is happening elsewhere)."
        ;;

      # StatusCommand::EXIT_PENDING_MIGRATIONS
      10)
        log_message WARNING "DB exists but has pending migrations - migrations need to run"
        if [ "$AUTO_RUN_MIGRATIONS" == "true" ]; then
          run_migrations
        fi
        ;;

      *)
        log_message ERROR "Unknown exit code from migrations:status: $status"
        exit 1
        ;;
    esac
  fi
}

#######################################################################
# Run the installer
#######################################################################

run_installer() {
  save_sentinel_runfile installer

  INSTALL_ADMIN_EMAIL=$(container-var INSTALL_ADMIN_EMAIL --default "admin@deskprodemo.com")
  rand_pass=$(openssl rand -hex 64)
  INSTALL_ADMIN_PASSWORD=$(container-var INSTALL_ADMIN_PASSWORD --default "$rand_pass")
  INSTALL_URL=$(container-var INSTALL_URL --default "http://127.0.0.1")

  log_message WARNING "Running: bin/install --url $INSTALL_URL --adminEmail $INSTALL_ADMIN_EMAIL --adminPassword XXXXXXXX"
  run_app_cmd bin/install --url "$INSTALL_URL" --adminEmail "$INSTALL_ADMIN_EMAIL" --adminPassword "$INSTALL_ADMIN_PASSWORD"

  status=$?

  if [ $status -ne 0 ]; then
    log_message ERROR "Installer failed with status $status"
    exit $status
  fi

  log_message INFO "Installer completed successfully"
  remove_sentinel_runfile installer
  rm -f /run/sim/needs-installer
}

#######################################################################
# Run migrations
#######################################################################

run_migrations() {
  save_sentinel_runfile migrations
  log_message WARNING "Running: php tools/migrations/artisan migrations:exec -vvv --run"

  run_app_cmd php tools/migrations/artisan migrations:exec -vvv --run
  status=$?

  if [ $status -ne 0 ]; then
    log_message ERROR "Migrations failed with status $status"
    exit $status
  fi

  log_message INFO "Migrations completed successfully"
  remove_sentinel_runfile migrations
  rm -f /run/sim/needs-migrations
}

#######################################################################
# Runs app command with sudo and logs the command output
#######################################################################
run_app_cmd() {
  export LOG_CHAN="task-stdout"
  sudo -E -u dp_app -D /srv/deskpro \
    "$@" 2>&1 \
    | while IFS= read -r line
      do
        log_message INFO "$line"
      done
  status="${PIPESTATUS[0]}"
  export LOG_CHAN=""

  return "$status"
}

#######################################################################
# Outputs a log message to stdout
#
# ARGUMENTS:
#  $1 - The log level (TRACE, DEBUG, INFO, WARNING, ERROR)
#  $2 - The log message
#######################################################################
log_message() {
  declare -A levels=([TRACE]=0 [DEBUG]=1 [INFO]=2 [WARNING]=3 [ERROR]=4)
  local lvl="${1^^}"
  local logline=""
  local chan="${LOG_CHAN}"

  if [ -n "$chan" ]; then
    chan="\"chan\":\"$chan\","
  else
    chan=" "
  fi
  logline="{\"ts\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"app\":\"container-ready\",${chan}\"lvl\":\"$lvl\",\"msg\":$(echo -n "$2" | jq -Rsa .),\"container_name\":\"$CONTAINER_NAME\",\"log_group\":\"docker-boot\"}"

  echo "$logline" >> /var/log/docker-boot.log

  LOGS_EXPORT_DIR=$(container-var LOGS_EXPORT_DIR --default "")
  if [ -n "$LOGS_EXPORT_DIR" ]; then
    echo "$logline" >> "$LOGS_EXPORT_DIR/docker-boot.log"
  fi

  [[ ${levels[$lvl]} ]] || return 0
  (( ${levels[$lvl]} < ${levels[$BOOT_LOG_LEVEL]} )) && return 0

  echo "$logline" >&2
}

#######################################################################
# Saves a sentinel file to /run to indicate when a task is running
#
# ARGUMENTS:
#  $1 - The name of the task
#######################################################################
save_sentinel_runfile() {
  local name="$1"
  local runfile="/run/container-running-$name"

  log_message TRACE "Saving sentinel file: $runfile"
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$runfile"
  chmod 0644 "$runfile"
}

#######################################################################
# Clears a sentinel file in /run for a given task
#
# ARGUMENTS:
#  $1 - The name of the task
#######################################################################
remove_sentinel_runfile() {
  local name="$1"
  local runfile="/run/container-running-$name"

  if [ -f "$runfile" ]; then
    log_message TRACE "Removing sentinel file: $runfile"
    rm -f "$runfile"
  fi
}

main
