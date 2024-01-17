<?php

$CONFIG = [];

//######################################################################
// data store
//######################################################################

/*
Primary DB connection that can perform normal CRUD operations.
Example:
  CREATE USER 'deskpro_primary'@'localhost' IDENTIFIED BY 'some-password';
  GRANT DELETE, SELECT, INSERT, LOCK TABLES, UPDATE ON `deskpro`.* TO 'deskpro_primary'@'localhost';
*/
$CONFIG['database'] = [
    'host' => 'is_changed_value',
    'user' => 'is_changed_value',
    'password' => 'is_changed_value',
    'dbname' => 'is_changed_value',
];

$CONFIG['database_advanced'] = ['read' => $CONFIG['database']];

$CONFIG['elastic'] = [
    'hosts' => ['is_changed_value'],
    'verify_ssl' => false,
    'retries' => 3,
    'index_name' => 'is_changed_value',
    'tenant_id' => 'is_changed_value',
];

$CONFIG['paths'] = [
    'var_path'   => 'is_changed_value',
    'blobs_path' => 'is_changed_value',
    'php_path' => 'is_changed_value',
    'mysqldump_path' => 'is_changed_value',
    'mysql_path' => 'is_changed_value',
];

$CONFIG['api_urls'] = [];

$CONFIG['app_key'] = 'is_changed_value';

$CONFIG['settings'] = [];
$CONFIG['settings']['core.filestorage_method'] = 'is_changed_value';
$CONFIG['settings']['api_auth.master_key'] = 'is_changed_value';
$CONFIG['settings']['arbitrary_key'] = 'is_changed_value';

$CONFIG['app_settings'] = [];
$CONFIG['app_settings']['arbitrary_key'] = 'is_changed_value';
