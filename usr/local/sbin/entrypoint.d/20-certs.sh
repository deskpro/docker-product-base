#!/bin/bash
#######################################################################
# This source handles installing custom SSL certificates or CA certs.
#######################################################################

certs_main() {
  custom_https_cert
  custom_ca_certs
  custom_mysql_cert
  update-ca-certificates
}

# HTTPS cert for web server to enable port 443
custom_https_cert() {
  if [ -f /deskpro/ssl/certs/deskpro-https.crt ] && [ -f /deskpro/ssl/private/deskpro-https.key ]; then
    boot_log_message INFO "Installing custom SSL certificate for HTTPS"
    cp /deskpro/ssl/certs/deskpro-https.crt /etc/ssl/certs/deskpro-https.crt
    cp /deskpro/ssl/private/deskpro-https.key /etc/ssl/private/deskpro-https.key
  elif [ "$(container-var HTTP_USE_TESTING_CERTIFICATE)" == "true" ]; then
    boot_log_message WARNING "Using testing SSL certificate for HTTPS"
    cp /usr/local/share/deskpro/deskpro-testing.crt /etc/ssl/certs/deskpro-https.crt
    cp /usr/local/share/deskpro/deskpro-testing.key /etc/ssl/private/deskpro-https.key
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
    cp -r /deskpro/ssl/ca-certificates/* /usr/local/share/ca-certificates/
    chown -R root:root /usr/local/share/ca-certificates
  fi
}

# MySQL connection cert to use from PHP
custom_mysql_cert() {
  if [ -f /deskpro/ssl/mysql/client.crt ] && [ -f /deskpro/ssl/mysql/client.key ]; then
    boot_log_message INFO "Installing custom MySQL SSL certificate"

    cp /deskpro/ssl/mysql/client.crt /srv/deskpro/INSTANCE_DATA/mysql-client.crt
    cp /deskpro/ssl/mysql/client.key /srv/deskpro/INSTANCE_DATA/mysql-client.key

    # and then put the CA cert into the OS dir
    if [ -f /deskpro/ssl/mysql/ca.pem ]; then
      cp /deskpro/ssl/mysql/ca.pem /usr/local/share/ca-certificates/deskpro-mysql-ca.pem
    fi
  fi
}

certs_main
unset certs_main custom_https_cert custom_ca_certs custom_mysql_cert
