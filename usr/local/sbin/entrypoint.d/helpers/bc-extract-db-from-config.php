#!/usr/bin/env php
<?php
// Usage: eval "$(bc-extract-db-from-config.php)"

// See 05-opc.sh::bc_opc_2_8()
// Extracts basic config into env vars so other templated files on this system can use them

require("/deskpro/config/deskpro-config.php");

$hostParts = explode(':', $CONFIG['database']['host'], 2);
if (count($hostParts) === 2) {
    $host = $hostParts[0];
    $port = $hostParts[1];
} else {
    $host = $hostParts[0];
}

echo 'export DESKPRO_DB_HOST="'.$host.'"';
echo "\n";

echo 'export DESKPRO_DB_PORT="'.($port ?? 3306).'"';
echo "\n";

echo 'export DESKPRO_DB_PASS_B64="'.base64_encode($CONFIG['database']['password']).'"';
echo "\n";

echo 'export DESKPRO_DB_NAME="'.$CONFIG['database']['dbname'].'"';
echo "\n";

if (!empty($CONFIG['app_key'])) {
    echo 'export DESKPRO_APP_KEY_B64="'.base64_encode($CONFIG['app_key']).'"';
    echo "\n";
}
