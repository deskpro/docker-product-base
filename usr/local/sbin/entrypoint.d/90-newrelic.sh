#!/bin/bash
#######################################################################
# This source handles setting environment variables required for 
# NewRelic.
#######################################################################

set_nr_env() {
    if [ "$DESKPRO_ENABLE_NEWRELIC" == "true" ]; then
        if [ -f /etc/deskpro-release ]; then
            source /etc/deskpro-release
        else
            boot_log_message DEBUG "[set_nr_env] Unable to load release file - attempting to load from env vars"
        fi
        boot_log_message DEBUG "[set_nr_env] Setting custom NewRelic env vars"
        export NEW_RELIC_METADATA_RELEASE_TAG=${DESKPRO_VERSION:-"Unknown"}
        export NEW_RELIC_METADATA_COMMIT=${DESKPRO_COMMIT_ID:-""}
    fi
}

set_nr_env
unset set_nr_env
