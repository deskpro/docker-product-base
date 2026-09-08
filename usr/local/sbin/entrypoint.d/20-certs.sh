#!/bin/bash
#######################################################################
# This source handles installing custom SSL certificates or CA certs.
#######################################################################

certs_main() {
  custom_https_cert
  custom_ca_certs
  custom_mysql_cert
  custom_mysql_ca
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

# MySQL client cert, for servers that authenticate with REQUIRE X509. Not
# needed just to encrypt the connection - mounting the CA alone does that.
custom_mysql_cert() {
  if [ -f /deskpro/ssl/mysql/client.crt ] && [ -f /deskpro/ssl/mysql/client.key ]; then
    boot_log_message INFO "Installing custom MySQL SSL client certificate"

    cp /deskpro/ssl/mysql/client.crt /srv/deskpro/INSTANCE_DATA/mysql-client.crt
    cp /deskpro/ssl/mysql/client.key /srv/deskpro/INSTANCE_DATA/mysql-client.key

    chown root:root /srv/deskpro/INSTANCE_DATA/mysql-client.crt
    chmod 0644 /srv/deskpro/INSTANCE_DATA/mysql-client.crt
    chown root:dp_app /srv/deskpro/INSTANCE_DATA/mysql-client.key
    chmod 0640 /srv/deskpro/INSTANCE_DATA/mysql-client.key
  fi
}

# MySQL server CA. Independent of the client cert above - a server that only
# does REQUIRE SSL needs the CA and no client cert at all.
#
# This is deliberately NOT installed into the system trust store: both PDO and
# the mysql client read the path we hand them verbatim, so the CA never needs
# to be in /etc/ssl/certs/ca-certificates.crt, and putting it there would
# trust it for curl, LDAP and every other TLS consumer in the image. Mount
# under /deskpro/ssl/ca-certificates/ if that is what you actually want.
custom_mysql_ca() {
  local src
  for src in /deskpro/ssl/mysql/ca.pem /deskpro/ssl/mysql/ca.crt; do
    if [ -f "$src" ]; then
      boot_log_message INFO "Installing custom MySQL CA certificate from $src"

      cp "$src" /srv/deskpro/INSTANCE_DATA/mysql-ca.crt
      chown root:root /srv/deskpro/INSTANCE_DATA/mysql-ca.crt
      chmod 0644 /srv/deskpro/INSTANCE_DATA/mysql-ca.crt
      return
    fi
  done
}

certs_main
unset certs_main custom_https_cert custom_ca_certs custom_mysql_cert custom_mysql_ca
