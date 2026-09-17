#!/bin/bash
#######################################################################
# Exports HTTP_PROXY/HTTPS_PROXY/ALL_PROXY/NO_PROXY (+lowercase) so
# services route egress through the local proxy. No-op when
# DISABLE_DESKPRO_PROXY_SERVICE=true. Runs before 40-evaluate-configs.sh
# so templates can read them.
#######################################################################

http_proxy_main() {
  if [ "${DISABLE_DESKPRO_PROXY_SERVICE:-false}" == "true" ]; then
    boot_log_message INFO "DISABLE_DESKPRO_PROXY_SERVICE=true - egress proxy env vars will not be set"
    return 0
  fi

  # Applies regardless of SVC_SMOKESCREEN_ENABLED/run mode -- e.g. in
  # "none" mode these still get baked into rendered configs even though
  # every program's autostart is false, which is harmless since nothing
  # is running to use them.
  local proxy_url="http://127.0.0.1:3128"
  local no_proxy_value
  no_proxy_value="$(build_no_proxy_default)"
  no_proxy_value="$(merge_config_php_hosts "$no_proxy_value")"

  export HTTP_PROXY="$proxy_url"
  export http_proxy="$proxy_url"
  export HTTPS_PROXY="$proxy_url"
  export https_proxy="$proxy_url"
  export ALL_PROXY="$proxy_url"
  export all_proxy="$proxy_url"
  export NO_PROXY="$no_proxy_value"
  export no_proxy="$no_proxy_value"

  boot_log_message TRACE "Egress proxy vars set: HTTP_PROXY=$proxy_url NO_PROXY=$no_proxy_value"
}

#######################################################################
# Extracts the host portion from a bare host or a URL
# (scheme://user:pass@host:port/path), dropping any port and path.
#
# ARGUMENTS:
#  $1 - The value to extract a host from
#######################################################################
extract_host() {
  local val="$1"
  [[ "$val" == *"://"* ]] && val="${val#*://}"
  [[ "$val" == *"@"* ]] && val="${val##*@}"
  val="${val%%/*}"
  val="${val%%:*}"
  printf '%s' "$val"
}

#######################################################################
# Builds the default NO_PROXY value: loopback, plus the host portion of
# every internal backend var below that has a value, plus any
# operator-set NO_PROXY entries appended on top of that (not replacing
# it). Deduplicates the final list.
#######################################################################
build_no_proxy_default() {
  local -a hosts=("localhost" "127.0.0.1" "::1" "host.docker.internal")
  local -a backend_vars=(
    DESKPRO_DB_HOST
    DESKPRO_DB_READ_HOST
    DESKPRO_DB_REPORTS_HOST
    DESKPRO_REDIS_HOST
    DESKPRO_REDIS_URL
    DESKPRO_ES_URL
    DESKPRO_ES_TIKA_HOST
    OTEL_EXPORTER_OTLP_ENDPOINT
  )
  local varname value host
  for varname in "${backend_vars[@]}"; do
    value="$(container-var "$varname")"
    [ -n "$value" ] || continue
    host="$(extract_host "$value")"
    [ -z "$host" ] && continue
    [[ "$host" == *","* ]] && continue
    hosts+=("$host")
  done

  if [ -n "${NO_PROXY:-}" ]; then
    local -a operator_hosts
    IFS=', ' read -ra operator_hosts <<< "$NO_PROXY"
    hosts+=("${operator_hosts[@]}")
  fi

  local -A seen=()
  local -a deduped=()
  for host in "${hosts[@]}"; do
    [ -z "$host" ] && continue
    if [ -z "${seen[$host]:-}" ]; then
      seen[$host]=1
      deduped+=("$host")
    fi
  done

  local IFS=,
  printf '%s' "${deduped[*]}"
}

#######################################################################
# Merges internal hosts read from dump-cfg (if present) into NO_PROXY.
# Falls back to the value passed in on any error.
#
# ARGUMENTS:
#  $1 - The NO_PROXY value built so far
#######################################################################
merge_config_php_hosts() {
  local no_proxy_so_far="$1"

  if [ ! -x /srv/deskpro/serve/bin/dump-cfg ]; then
    printf '%s' "$no_proxy_so_far"
    return 0
  fi

  local json
  if ! json="$(/srv/deskpro/serve/bin/dump-cfg 2>/dev/null)"; then
    printf '%s' "$no_proxy_so_far"
    return 0
  fi

  if ! jq -e . >/dev/null 2>&1 <<< "$json"; then
    printf '%s' "$no_proxy_so_far"
    return 0
  fi

  # Only present (non-null) keys are used.
  local -a config_values=()
  local raw
  while IFS= read -r raw; do
    [ -n "$raw" ] && config_values+=("$raw")
  done < <(jq -r '
    [
      .database.primary.host, .database.read.host, .database.reports.host,
      .services.apiv2.url, .services.apiv1.url, .services.channels.url, .services.blobs.url,
      .elastic.host, .elastic.tika_host,
      .redis.host, .redis.url,
      .otel.endpoint
    ] | .[] | select(. != null)
  ' <<< "$json" 2>/dev/null)

  if [ "${#config_values[@]}" -eq 0 ]; then
    printf '%s' "$no_proxy_so_far"
    return 0
  fi

  local -a hosts
  IFS=',' read -ra hosts <<< "$no_proxy_so_far"

  local value host
  for value in "${config_values[@]}"; do
    host="$(extract_host "$value")"
    [ -z "$host" ] && continue
    [[ "$host" == *","* ]] && continue
    hosts+=("$host")
  done

  local -A seen=()
  local -a deduped=()
  for host in "${hosts[@]}"; do
    [ -z "$host" ] && continue
    if [ -z "${seen[$host]:-}" ]; then
      seen[$host]=1
      deduped+=("$host")
    fi
  done

  local IFS=,
  printf '%s' "${deduped[*]}"
}

http_proxy_main
unset http_proxy_main extract_host build_no_proxy_default merge_config_php_hosts
