<?php
// === DATABASE SETTINGS ===
$CONF['database_type'] = 'mysqli';
$CONF['database_host'] = 'localhost';
$CONF['database_user'] = '{{IWB_POSTFIXADMIN_SQL_USER}}';
$CONF['database_password'] = '{{IWB_POSTFIXADMIN_SQL_PASSWORD}}';
$CONF['database_name'] = '{{IWB_POSTFIXADMIN_SQL_DBNAME}}';

// === GENERAL SETTINGS ===
$CONF['configured'] = true;
$CONF['default_language'] = 'en';
$CONF['domain_path'] = 'NO';
$CONF['domain_in_mailbox'] = 'YES';
$CONF['fetchmail'] = 'NO';
$CONF['quota'] = 'YES';

// === PASSWORD ENCRYPTION ===
$CONF['encrypt'] = 'md5crypt';
$CONF['dovecotpw'] = "/usr/bin/doveadm pw";

// === SETUP PASSWORD HASH ===
$CONF['setup_password'] = '{{IWB_POSTFIXADMIN_SETUP_PASSWORD_HASH}}';

// === SITE OPTIONS ===
$CONF['admin_email'] = '{{IWB_MAIL_USER}}@{{IWB_DOMAIN}}';
$CONF['site_name'] = 'PostfixAdmin for {{IWB_DOMAIN}}';

?>
