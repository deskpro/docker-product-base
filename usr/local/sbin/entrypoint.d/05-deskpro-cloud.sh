#!/bin/bash
#######################################################################
# This source handles setup steps for Deskpro Cloud.
#######################################################################

function deskpro_cloud_main() {
  if [ -z "$DESKPRO_CLOUD_MODE" ]; then
    boot_log_message TRACE "[cloud] Not running in Cloud mode, skipping cloud setup."
    return
  fi
  echo "set nocompatible" >> /etc/vim/vimrc.local
}

deskpro_cloud_main
unset deskpro_cloud_main
