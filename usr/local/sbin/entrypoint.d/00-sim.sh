#!/bin/bash
#######################################################################
# This source just activates various release simulation features
# for testing the container without a full Deskpro release.
#######################################################################

sim_main() {
  if [ "$SIM_RELEASE" == "true" ]; then
    boot_log_message WARNING "[SIM] Installing test source files because SIM_RELEASE=true"

    if ! grep -q -w 'DESKPRO_VERSION="0.0.0"' /etc/deskpro-release; then
      boot_log_message ERROR "[SIM] Cannot use SIM_RELEASE=true with a real Deskpro release."
      exit 1
    fi

    sim_install
  else
    # If there is no root, we will create it now with a placeholder (e.g. base image without Deskpro on it yet)
    if [ ! -d /srv/deskpro/serve/www ]; then
      boot_log_message ERROR "Source files not detected."

      mkdir -p /srv/deskpro/serve/www
      echo "Missing source files." > /srv/deskpro/serve/www/index.php
    fi
  fi
}

sim_install() {
  for f in /usr/local/share/deskpro/simulate-release/*; do
    basef=$(basename "$f")
    if [ -d "$f" ] && [ ! -d /srv/deskpro/$basef ]; then
      ln -sf $f /srv/deskpro/$basef
    fi
  done
  chmod 0755 /srv/deskpro

  if [ ! -d /run/sim ]; then
    mkdir /run/sim
    chmod 0777 /run/sim
  fi

  # Using env vars as an easy way to enable the sentinel files.
  # But using sentinel files at all because then you can perform a full e2e test
  # (e.g. reboot after "migrations" are run to verify behaviour the second time).
  # So it depends on the use-case of your test if you want to mount /run/sim or just use env vars.

  if [ "$SIM_NEEDS_INSTALLER" == "true" ]; then
    boot_log_message WARNING "[SIM] Enabling /run/sim/needs-installer (SIM_NEEDS_INSTALLER=true)"
    touch /run/sim/needs-installer
  fi

  if [ "$SIM_NEEDS_MIGRATIONS" == "true" ]; then
    boot_log_message WARNING "[SIM] Enabling /run/sim/needs-migrations (SIM_NEEDS_MIGRATIONS=true)"
    touch /run/sim/needs-migrations
  fi

  if [ "$SIM_HEALTHCHECK_FAIL" == "true" ]; then
    boot_log_message WARNING "[SIM] Enabling /run/healthcheck-force-failure (SIM_HEALTHCHECK_FAIL=true)"
    touch /run/healthcheck-force-failure
  fi
}

sim_main
unset sim_main sim_install
