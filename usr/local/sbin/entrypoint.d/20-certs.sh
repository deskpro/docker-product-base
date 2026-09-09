#!/bin/bash
#######################################################################
# This source handles installing custom SSL certificates or CA certs.
#######################################################################

certs_main() {
  custom_https_cert
  custom_ca_certs
  custom_mysql_cert
  if [ "$UPDATE_CERT_BUNDLE" = true ]; then
    boot_log_message INFO "Updating CA certificate bundle"
    update-ca-certificates
  fi
}

# HTTPS cert for web server to enable port 443
custom_https_cert() {
  if [ -f /deskpro/ssl/certs/deskpro-https.crt ] && [ -f /deskpro/ssl/private/deskpro-https.key ]; then
    boot_log_message INFO "Installing custom SSL certificate for HTTPS"
    cp /deskpro/ssl/certs/deskpro-https.crt /etc/ssl/certs/deskpro-https.crt
    cp /deskpro/ssl/private/deskpro-https.key /etc/ssl/private/deskpro-https.key
    export UPDATE_CERT_BUNDLE=true
  elif [ "$(container-var HTTP_USE_TESTING_CERTIFICATE)" == "true" ]; then
    boot_log_message WARNING "Using testing SSL certificate for HTTPS"
    cp /usr/local/share/deskpro/deskpro-testing.crt /etc/ssl/certs/deskpro-https.crt
    cp /usr/local/share/deskpro/deskpro-testing.key /etc/ssl/private/deskpro-https.key
    export UPDATE_CERT_BUNDLE=true
  fi

  if [ -f "/etc/ssl/certs/deskpro-https.crt" ]; then
    chown root:root /etc/ssl/certs/deskpro-https.crt /etc/ssl/private/deskpro-https.key
    chmod 0644 /etc/ssl/certs/deskpro-https.crt
    chmod 0600 /etc/ssl/private/deskpro-https.key
  fi
}

# Custom CA certs to trust
custom_ca_certs() {
  if [ -d /deskpro/ssl/ca-certificates ]; then
    boot_log_message INFO "Installing custom CA certificates"
    rsync -aL --exclude='.*' /deskpro/ssl/ca-certificates/ /usr/local/share/ca-certificates/
    chown -R root:root /usr/local/share/ca-certificates
    export UPDATE_CERT_BUNDLE=true
  fi
}

# Tests whether a MySQL cert path has been mounted.
#
# Anything present at the path that is not a readable regular file (a dangling
# symlink, a directory) is a misconfiguration: it would otherwise be
# indistinguishable from "not mounted" and silently downgrade the connection.
#
# ARGUMENTS:
#  $1 - Path to test
#
# RETURN:
#  0 - Mounted and usable
#  1 - Not mounted
#######################################################################
mysql_cert_mounted() {
  if [ -f "$1" ]; then
    return 0
  fi

  if [ -e "$1" ] || [ -L "$1" ]; then
    boot_log_message ERROR "$1 is mounted but is not a readable file"
    exit 1
  fi

  return 1
}

# Installs one connection's MySQL certificates out of a mount directory.
#
# The client cert/key pair and the CA cert are independent of each other:
#  - client.crt + client.key  ->  client certificate auth (MySQL REQUIRE X509)
#  - ca.pem                   ->  verify the server against a specific CA, with
#                                 or without a client certificate
#
# ARGUMENTS:
#  $1 - Mount directory to install certificates from
#  $2 - INSTANCE_DATA filename prefix to install them under
#######################################################################
install_mysql_certs() {
  local src="$1"
  local dest="/srv/deskpro/INSTANCE_DATA/$2"
  local has_crt=false
  local has_key=false

  if mysql_cert_mounted "$src/client.crt"; then
    has_crt=true
  fi

  if mysql_cert_mounted "$src/client.key"; then
    has_key=true
  fi

  if [ "$has_crt" != "$has_key" ]; then
    boot_log_message ERROR "Incomplete MySQL client certificate: both $src/client.crt and $src/client.key must be mounted"
    exit 1
  fi

  if [ "$has_crt" == true ]; then
    boot_log_message INFO "Installing custom MySQL SSL client certificate from $src/"

    if ! cp "$src/client.crt" "$dest-client.crt" ||
      ! cp "$src/client.key" "$dest-client.key"; then
      boot_log_message ERROR "Failed to install MySQL client certificate from $src/"
      exit 1
    fi
  fi

  if mysql_cert_mounted "$src/ca.pem"; then
    boot_log_message INFO "Installing custom MySQL CA certificate from $src/ca.pem"

    if ! cp "$src/ca.pem" "$dest-ca.pem"; then
      boot_log_message ERROR "Failed to install MySQL CA certificate from $src/ca.pem"
      exit 1
    fi

    # a CA cert is public, but PHP-FPM runs as dp_app and must be able to read it
    chown root:root "$dest-ca.pem"
    chmod 0644 "$dest-ca.pem"
  fi
}

# Every INSTANCE_DATA file custom_mysql_cert manages, in install order.
MYSQL_CERT_PREFIXES="mysql mysql-read mysql-reports"

# Resolves whether a connection asked for something, honouring "explicitly set
# wins, unset inherits from the primary".
#
# An unset variable is materialised nowhere, so container-var gives us "" for
# it, which is what separates "unset" from "set to false".
#
# ARGUMENTS:
#  $1 - Env var name for this connection
#  $2 - Value inherited from the primary when this one is unset
#
# RETURN:
#  0 - Truthy
#  1 - Falsey
#######################################################################
mysql_tls_flag() {
  local value
  value="$(container-var "$1")"

  if [ -z "$value" ]; then
    [ "$2" == true ]
    return
  fi

  # matches what gomplate's conv.ToBool accepts, so the boot check and the
  # templates agree on what the operator asked for
  case "${value,,}" in
    true | 1 | yes | on | t) return 0 ;;
    *) return 1 ;;
  esac
}

# Refuses the boot when a connection is set to verify the server certificate
# but has no CA file to verify it against.
#
# PDO's MYSQL_ATTR_SSL_CA wants a file. The /etc/ssl/certs fallback the
# templates use is a directory, which OpenSSL will not load as a CA bundle, so
# the connection would fail on its first query instead - long after the
# container looked healthy. Say so here, where the message can be specific.
#
# Mirrors the resolution in deskpro-config.php.tmpl and user.my.cnf.tmpl. All
# three have to agree; change them together.
#
# ARGUMENTS:
#  $1 - Env var infix: "" for the primary, "READ_" or "REPORTS_"
#  $2 - INSTANCE_DATA filename prefix for this connection
#  $3 - Mount directory, for the error message
#######################################################################
check_mysql_tls() {
  local infix="$1"
  local dest="/srv/deskpro/INSTANCE_DATA/$2"
  local src="$3"
  local primary=/srv/deskpro/INSTANCE_DATA/mysql
  local enabled=false
  local parent_enabled=false
  local parent_verify=false

  # A connection that supplied any certificate of its own is described by its
  # own directory alone. One that supplied none inherits the primary's set.
  if [ -n "$infix" ] &&
    [ ! -f "$dest-ca.pem" ] && [ ! -f "$dest-client.crt" ] && [ ! -f "$dest-client.key" ]; then
    dest="$primary"
    # point the operator at the directory the certificates would actually
    # come from, not the empty one
    src=/deskpro/ssl/mysql
  fi

  if [ -n "$infix" ]; then
    if [ -f "$primary-ca.pem" ] || { [ -f "$primary-client.crt" ] && [ -f "$primary-client.key" ]; }; then
      parent_enabled=true
    elif mysql_tls_flag DESKPRO_DB_SSL_ENABLED false; then
      parent_enabled=true
    fi

    if mysql_tls_flag DESKPRO_DB_SSL_VERIFY_SERVER_CERT false; then
      parent_verify=true
    fi
  fi

  if [ -f "$dest-ca.pem" ] || { [ -f "$dest-client.crt" ] && [ -f "$dest-client.key" ]; }; then
    enabled=true
  elif mysql_tls_flag "DESKPRO_DB_${infix}SSL_ENABLED" "$parent_enabled"; then
    enabled=true
  fi

  if [ "$enabled" != true ]; then
    return 0
  fi

  if ! mysql_tls_flag "DESKPRO_DB_${infix}SSL_VERIFY_SERVER_CERT" "$parent_verify"; then
    return 0
  fi

  if [ ! -f "$dest-ca.pem" ]; then
    boot_log_message ERROR "DESKPRO_DB_${infix}SSL_VERIFY_SERVER_CERT is set but no CA certificate is available: mount one at $src/ca.pem"
    exit 1
  fi
}

# MySQL connection certs to use from PHP and the mysql helper CLIs.
#
# Each of the three database connections can carry its own certificates - they
# may be different servers behind different CAs:
#
#  /deskpro/ssl/mysql/          ->  primary  ->  INSTANCE_DATA/mysql-*
#  /deskpro/ssl/mysql/read/     ->  read     ->  INSTANCE_DATA/mysql-read-*
#  /deskpro/ssl/mysql/reports/  ->  reports  ->  INSTANCE_DATA/mysql-reports-*
#
# Mounting any certificate for a connection makes that directory the whole
# story for it - nothing is inherited from the primary. Mount none and it uses
# the primary's set. deskpro-config.php.tmpl and user.my.cnf.tmpl apply that
# same rule to the files installed here.
custom_mysql_cert() {
  local prefix

  # INSTANCE_DATA outlives the container, so last boot's copies have to go
  # first: a directory that is no longer mounted must read as "supplied
  # nothing", or a stale file would keep overriding the primary's certificates
  # after the operator removed the mount.
  for prefix in $MYSQL_CERT_PREFIXES; do
    rm -f "/srv/deskpro/INSTANCE_DATA/$prefix-ca.pem" \
      "/srv/deskpro/INSTANCE_DATA/$prefix-client.crt" \
      "/srv/deskpro/INSTANCE_DATA/$prefix-client.key"
  done

  install_mysql_certs /deskpro/ssl/mysql mysql
  install_mysql_certs /deskpro/ssl/mysql/read mysql-read
  install_mysql_certs /deskpro/ssl/mysql/reports mysql-reports

  check_mysql_tls "" mysql /deskpro/ssl/mysql

  # only connections that are actually configured are worth failing over
  if [ -n "$(container-var DESKPRO_DB_READ_HOST)" ]; then
    check_mysql_tls READ_ mysql-read /deskpro/ssl/mysql/read
  fi

  if [ -n "$(container-var DESKPRO_DB_REPORTS_HOST)" ]; then
    check_mysql_tls REPORTS_ mysql-reports /deskpro/ssl/mysql/reports
  fi
}

certs_main
unset certs_main custom_https_cert custom_ca_certs custom_mysql_cert install_mysql_certs mysql_cert_mounted mysql_tls_flag check_mysql_tls MYSQL_CERT_PREFIXES
