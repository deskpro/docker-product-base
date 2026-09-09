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

# MySQL connection certs to use from PHP.
#
# The client cert/key pair and the CA cert are independent of each other:
#  - client.crt + client.key  ->  client certificate auth (MySQL REQUIRE X509)
#  - ca.pem                   ->  verify the server against a specific CA, with
#                                 or without a client certificate
#
# Both are installed into INSTANCE_DATA; deskpro-config.php.tmpl gates the PDO
# SSL options on their presence there.
custom_mysql_cert() {
  local has_crt=false
  local has_key=false

  if mysql_cert_mounted /deskpro/ssl/mysql/client.crt; then
    has_crt=true
  fi

  if mysql_cert_mounted /deskpro/ssl/mysql/client.key; then
    has_key=true
  fi

  if [ "$has_crt" != "$has_key" ]; then
    boot_log_message ERROR "Incomplete MySQL client certificate: both /deskpro/ssl/mysql/client.crt and /deskpro/ssl/mysql/client.key must be mounted"
    exit 1
  fi

  if [ "$has_crt" == true ]; then
    boot_log_message INFO "Installing custom MySQL SSL client certificate"

    if ! cp /deskpro/ssl/mysql/client.crt /srv/deskpro/INSTANCE_DATA/mysql-client.crt ||
      ! cp /deskpro/ssl/mysql/client.key /srv/deskpro/INSTANCE_DATA/mysql-client.key; then
      boot_log_message ERROR "Failed to install MySQL client certificate from /deskpro/ssl/mysql/"
      exit 1
    fi
  fi

  if mysql_cert_mounted /deskpro/ssl/mysql/ca.pem; then
    boot_log_message INFO "Installing custom MySQL CA certificate"

    if ! cp /deskpro/ssl/mysql/ca.pem /srv/deskpro/INSTANCE_DATA/mysql-ca.pem; then
      boot_log_message ERROR "Failed to install MySQL CA certificate from /deskpro/ssl/mysql/ca.pem"
      exit 1
    fi

    # a CA cert is public, but PHP-FPM runs as dp_app and must be able to read it
    chown root:root /srv/deskpro/INSTANCE_DATA/mysql-ca.pem
    chmod 0644 /srv/deskpro/INSTANCE_DATA/mysql-ca.pem
  fi
}

certs_main
unset certs_main custom_https_cert custom_ca_certs custom_mysql_cert mysql_cert_mounted
