#!/usr/bin/env php
<?php
// See 05-opc.sh::bc_opc_2_8()

require("/deskpro/config/deskpro-config.php");

[$host, $port] = explode(':', $CONFIG['database']['host'], 2);

echo 'export DESKPRO_DB_HOST="'.$host.'"';
echo "\n";

echo 'export DESKPRO_DB_PORT="'.($port ?? 3306).'"';
echo "\n";

echo 'export DESKPRO_DB_PASS_B64="'.base64_encode($CONFIG['database']['password']).'"';
echo "\n";

echo 'export DESKPRO_DB_NAME="'.base64_encode($CONFIG['database']['dbname']).'"';
echo "\n";
