#!/bin/bash
#######################################################################
# This source handles installed patched files from the user.
#######################################################################

patches_main() {
  # special dir that means "any" (or dev)
  install_patches "0.0.0"

  # but normally only apply patches for the same version
  if [ -d "/srv/deskpro/deskpro-build.json" ]; then
    deskpro_version=$(jq -r '.build.coreVersion' /srv/deskpro/deskpro-build.json)
    install_patches "$deskpro_version"
  fi
}

#######################################################################
# Installs patched files from a directory into deskpro source
#
# ARGUMENTS:
#  $1 - Patch directory (a version string)
#######################################################################
install_patches() {
  if [ -d "/deskpro/config/patches/$1" ]; then
    boot_log_message INFO "Installing patched files from /deskpro/config/patches/$1"
    rsync -rlptD "/deskpro/config/patches/$1/" "/srv/deskpro/"
  fi
}

patches_main
unset patches_main install_patches
