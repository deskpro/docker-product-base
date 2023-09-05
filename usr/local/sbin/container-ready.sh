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

  if [ "$LOGS_OUTPUT_FORMAT" == "logfmt" ]; then
    if [ -n "$chan" ]; then
      chan=" chan=$chan "
    else
      chan=" "
    fi
    logline="ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ") app=container-ready${chan}lvl=$lvl msg=$(echo -n "$2" | jq -Rsa .) container_name=$CONTAINER_NAME"
  else
    if [ -n "$chan" ]; then
      chan="\"chan\":\"$chan\","
    else
      chan=" "
    fi
    logline="{\"ts\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"app\":\"container-ready\",${chan}\"lvl\":\"$lvl\",\"msg\":$(echo -n "$2" | jq -Rsa .),\"container_name\":\"$CONTAINER_NAME\"}"
  fi

  echo "$logline" >> /var/log/docker-boot.log

  if [ -n "$LOGS_EXPORT_DIR" ]; then
    echo "$logline" >> "$LOGS_EXPORT_DIR/docker-boot.log"
  fi

  [[ ${levels[$lvl]} ]] || return 0
  (( ${levels[$lvl]} < ${levels[$BOOT_LOG_LEVEL]} )) && return 0

  echo "$logline" >&2
}

main
