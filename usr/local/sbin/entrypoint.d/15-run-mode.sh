#!/bin/bash
#######################################################################
# This source looks at the DOCKER_CMD and DOCKER_CMD_ARGS to determine
# what services should be started.
#
# It will set DOCKER_EXEC to one of the following:
#   supervisord
#   bash
#   exec
#
# And optionally DOCKER_EXEC_ARGS to an array of arguments to pass to
# the DOCKER_EXEC command (e.g. exec).
#
# For DOCKER_EXEC=supervisord, it will also set the various SVC_*_ENABLED
# variables that get used from the supervisord conf templates to deterine
# "autostart" of various services, which effectively starts the services
# for the given run mode the user wants.
#######################################################################

export DOCKER_EXEC=""
export DOCKER_EXEC_ARGS=()
export IS_EXEC_MODE=""

function run_mode_main() {
  local auto_start_services=()

  case "$DOCKER_CMD" in
    web)
      auto_start_services+=("web")
      export DOCKER_EXEC="supervisord"
      ;;

    email_collect)
      auto_start_services+=("email_collect")
      export DOCKER_EXEC="supervisord"
      ;;

    email_process)
      auto_start_services+=("email_process")
      export DOCKER_EXEC="supervisord"
      ;;

    tasks)
      auto_start_services+=("tasks")
      export DOCKER_EXEC="supervisord"
      ;;

    combined)
      auto_start_services+=("web" "tasks")
      export DOCKER_EXEC="supervisord"
      ;;

    svc)
      auto_start_services=("${auto_start_services[@]}" "${DOCKER_CMD_ARGS[@]}")
      export DOCKER_EXEC="supervisord"
      ;;

    none)
      export DOCKER_EXEC="supervisord"
      ;;

    bash)
      export DOCKER_EXEC="bash"
      export DOCKER_EXEC_ARGS=("${DOCKER_CMD_ARGS[@]}")
      export IS_EXEC_MODE="true"
      ;;

    exec)
      export DOCKER_EXEC="exec"
      export DOCKER_EXEC_ARGS=("${DOCKER_CMD_ARGS[@]}")
      export IS_EXEC_MODE="true"
      ;;

    *)
      boot_log_message ERROR "Unknown run mode: $DOCKER_CMD"
      ;;
  esac

  boot_log_message TRACE "DOCKER_EXEC=$DOCKER_EXEC"

  for svcId in "${auto_start_services[@]}"; do
    case "$svcId" in
      web|http|nginx|php_fpm)
        export SVC_NGINX_ENABLED=true
        export SVC_PHP_FPM_ENABLED=true
        boot_log_message INFO "Enabling services: nginx php_fpm"
        ;;
      tasks)
        export SVC_TASKS_ENABLED=true
        boot_log_message INFO "Enabling services: tasks"
        ;;
      email_collect)
        export SVC_EMAIL_COLLECT_ENABLED=true
        export TASKS_DISABLE_EMAIL_IN_JOB=true
        boot_log_message INFO "Enabling services: email_collect"
        ;;
      email_process)
        export SVC_EMAIL_PROCESS_ENABLED=true
        export TASKS_DISABLE_EMAIL_IN_JOB=true
        boot_log_message INFO "Enabling services: email_process"
        ;;
      *)
        boot_log_message ERROR "Unknown service: $svcId"
        ;;
    esac
  done

  # these run modes may call Deskpro internal APIs...
  local uses_internal_api=""
  if [ ${#auto_start_services[@]} -ne 0 ] || [ "$DOCKER_EXEC" == "exec" ] || [ "$DOCKER_EXEC" == "bash" ]; then
    uses_internal_api="true"
  fi

  # ... if we may be calling internal APIs,
  # and the internal API is configured as localhost (default)
  # and it's not already running -> then we need to run locally
  if [ "$uses_internal_api" == "true" ] && [ -z "$SVC_NGINX_ENABLED" ] && [ "${DESKPRO_API_BASEURL_PRIVATE:-http://127.0.0.1:80}" == "http://127.0.0.1:80" ]; then
    boot_log_message TRACE "Starting nginx and fpm for internal api calls"
    export SVC_NGINX_ENABLED=true
    export SVC_PHP_FPM_ENABLED=true

    # used by php config templates to reduce memory usage
    export HTTP_INTERNAL_MODE="true"
  fi
}

run_mode_main
unset run_mode_main
