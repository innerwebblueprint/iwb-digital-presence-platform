#!/bin/bash
# includes/setup/scripts/setup-env.sh

: "${IWB_DOMAIN:?IWB_DOMAIN not set}"
: "${IWB_MAIL_USER:?$IWB_MAIL_USER not set}"
: "${IWB_MAIL_PASS:?$IWB_MAIL_PASS not set}"
: "${IWB_STORJ_WPOPS_BUCKET:?IWB_STORJ_WPOPS_BUCKET not set}"


# === Output Styling ===
export IWB_RED=$(printf '\033[0;31m')
export IWB_GREEN=$(printf '\033[0;32m')
export IWB_BLUE=$(printf '\033[0;34m')
export IWB_RESET=$(printf '\033[0m')
export IWB_PREFIX="${IWB_GREEN}[${IWB_RED}I${IWB_GREEN}W${IWB_BLUE}B${IWB_GREEN}]${IWB_RESET}"
export ERR_PREFIX="${IWB_RED}ERROR${IWB_RESET}"

# === Core Directories ===
export IWB_SCRIPTSDIR="/var/setup/scripts"
export IWB_CONFIGDIR="/var/setup/configs"

# === Persistent Data Directories ===
export IWB_DATA_ROOT="/var/data"
export IWB_STATE_DIR="${IWB_DATA_ROOT}/state"
export IWB_BACKUP_DIR="${IWB_DATA_ROOT}/backups"

# === State Flags ===
export IWB_DB_INIT_FLAG="${IWB_STATE_DIR}/db_initialized"
export IWB_POSTFIXADMIN_CONFIGURED_FLAG="${IWB_STATE_DIR}/postfixadmin_configured"
export IWB_POSTFIXADMIN_SCHEMA_FLAG="${IWB_STATE_DIR}/postfixadmin_schema_initialized"
export IWB_MARIADB_PID_FILE="${IWB_STATE_DIR}/mariadb-setup.pid"

# === Storj Backup Keys ===
export IWB_PA_SQL_BACKUP_PATH="${IWB_BACKUP_DIR}/postfixadmin.sql"
export IWB_MAIL_BACKUP_PATH="${IWB_BACKUP_DIR}/maildir.tar.gz"

export IWB_STORJ_PA_DB_KEY="sj://${IWB_STORJ_WPOPS_BUCKET}/mail/db/postfixadmin_${IWB_DOMAIN}.sql"
export IWB_STORJ_MAIL_KEY="sj://${IWB_STORJ_WPOPS_BUCKET}/mail/email/${IWB_DOMAIN}_maildir.tar.gz"
export IWB_STORJ_CERT_BACKUP_KEY="sj://${IWB_STORJ_WPOPS_BUCKET}/certs/${IWB_DOMAIN}_certs.tar.gz"
export IWB_DKIM_CERT_BACKUP_KEY="sj://${IWB_STORJ_WPOPS_BUCKET}/certs/${IWB_DOMAIN}_dkim_certs.tar.gz"

# === Database Admin ===
# Generate password if not already set
if [ -z "${IWB_MYSQL_ROOT_PASSWORD}" ]; then
  export IWB_MYSQL_ROOT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20)
  echo "$IWB_PREFIX No Root password provided for Database Admin — generated one automatically."
fi

# === PostfixAdmin Config ===
export IWB_POSTFIXADMIN_TEMPLATE="/var/setup/configs/mail/postfixadmin/config.local.template.php"
export IWB_POSTFIXADMIN_CONFIG_OUT="/var/setup/configs/mail/postfixadmin/config.local.php"
export IWB_POSTFIXADMIN_SYMLINK="/var/www/html/postfixadmin/config.local.php"
export IWB_POSTFIXADMIN_SETUP_PASSWORD="iwb-internal-setup"

export IWB_POSTFIXADMIN_SQL_DBNAME="${IWB_POSTFIXADMIN_SQL_DBNAME:-postfixadmin}"
export IWB_POSTFIXADMIN_SQL_USER="${IWB_POSTFIXADMIN_SQL_USER:-postfixadmin}"
# Generate password if not already set
if [ -z "${IWB_POSTFIXADMIN_SQL_PASSWORD}" ]; then
  export IWB_POSTFIXADMIN_SQL_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20)
  echo "$IWB_PREFIX No DB password provided for PostfixAdmin — generated one automatically."
fi

# === RSPAMD Config === #
# These are configured in your .env as you may want to use them to access the
# web administration interface
#IWB_RSPAMD_CONTROLLER_PASSWORD="your_pass"
#IWB_RSPAMD_CONTROLLER_ENABLE_PASSWORD="your_enable_pass"


# === Webroot Directories ===
export IWB_WEB_WP="/var/www/html/wordpress"
export IWB_WEB_POSTFIX="/var/www/html/postfixadmin/public"
export IWB_WEB_WEBMAIL="/var/www/html/webmail/public"
export IWB_HTML_TEMPLATE_DIR="/var/setup/html"


# === SSL Template Directory ===
export IWB_SSL_TEMPLATE_DIR="${IWB_CONFIGDIR}/http/nginx/sites-available"
export IWB_NGINX_CONF_DIR="/etc/nginx/http.d"
export IWB_CERT_BACKUP_DIR="/tmp/cert-backups"


# === PHP Config Files ===
export IWB_PHP_FPM_CONF="/etc/php81/php-fpm.conf"
export IWB_PHP_POOL_CONF="/etc/php81/php-fpm.d/www.conf"

# === Logging / Service Configs ===
export IWB_RSYSLOG_CONF="/etc/rsyslog.d/10-postfix.conf"
export IWB_SUPERVISOR_CONF="/etc/supervisor/conf.d/supervisord.conf"
