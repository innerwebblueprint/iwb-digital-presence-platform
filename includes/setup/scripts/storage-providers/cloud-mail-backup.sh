#!/bin/bash
# includes/setup/scripts/storage-providers/cloud-mail-backup.sh

set -e

# Validate required variables
: "${IWB_PA_SQL_BACKUP_PATH:?IWB_PA_SQL_BACKUP_PATH not set}"
: "${IWB_STORJ_PA_DB_KEY:?IWB_STORJ_PA_DB_KEY not set}"
: "${IWB_POSTFIXADMIN_SQL_DBNAME:?IWB_POSTFIXADMIN_SQL_DBNAME not set}"
: "${IWB_MYSQL_ROOT_PASSWORD:?IWB_MYSQL_ROOT_PASSWORD not set}"

echo "$IWB_PREFIX Backing up PostfixAdmin database to Storj..."

# Dump the postfixadmin DB
mkdir -p "$(dirname "$IWB_PA_SQL_BACKUP_PATH")"
mariadb-dump --databases "${IWB_POSTFIXADMIN_SQL_DBNAME}" -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" > "$IWB_PA_SQL_BACKUP_PATH"


# Upload to Storj
if uplink cp "$IWB_PA_SQL_BACKUP_PATH" "$IWB_STORJ_PA_DB_KEY"; then
  echo "$IWB_PREFIX Database backup successfully uploaded to Storj."
else
  echo "$ERR_PREFIX Failed to upload database backup to Storj."
  return 1
fi

# (Mail backup will be added later when mail exists)

