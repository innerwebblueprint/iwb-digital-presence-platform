#!/bin/bash
# includes/setup/scripts/storage-providers/cloud-mail-restore.sh

set -e

# Validate required variables
: "${IWB_STORJ_PA_DB_KEY:?IWB_STORJ_PA_DB_KEY not set}"
: "${IWB_PA_SQL_BACKUP_PATH:?IWB_PA_SQL_BACKUP_PATH not set}"
: "${IWB_MYSQL_ROOT_PASSWORD:?IWB_MYSQL_ROOT_PASSWORD not set}"

# Try to restore from Storj
echo "$IWB_PREFIX Checking for PostfixAdmin SQL backup on Storj..."
if uplink cp "$IWB_STORJ_PA_DB_KEY" "$IWB_PA_SQL_BACKUP_PATH" > /dev/null 2>&1; then
  echo "$IWB_PREFIX Downloaded SQL backup successfully. Importing..."
  mysql -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" < "$IWB_PA_SQL_BACKUP_PATH"
else
  echo "$IWB_PREFIX Backup not found on Storj. Skipping restore."
  return 1
fi
