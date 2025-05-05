#!/bin/bash
# includes/setup/scripts/backup/iwb-backup.sh

# Usage: ./iwb-backup.sh <dataset> <interval>
# Datasets: mail, postfix, ssl, dkim, rspamd, wpdb, wphtml
# Intervals: snapshot, hourly, daily, weekly, monthly, yearly

# --- Configuration ---
MODULE="BACKUP"
LOG_FILE="/var/log/iwb-backup.log"

# Load environment and functions
source /var/setup/scripts/setup-env.sh
source /var/setup/scripts/storage-providers/storj/storj-functions.sh

# Redirect all output of log function to both console and log file
exec > >(tee -a "$LOG_FILE") 2>&1


# --- Input Validation ---
DATASET="$1"
INTERVAL="$2"

if [ -z "$DATASET" ] || [ -z "$INTERVAL" ]; then
  log "$ERR_PREFIX: Usage: $0 <dataset> <interval>"
  (return 1 2>/dev/null) || exit 1
fi

# --- Timestamp Naming ---
case "$INTERVAL" in
  snapshot)
    TIMESTAMP="$(date +%Y_%m_%d)"
    ;;
  hourly)
    TIMESTAMP="$(date +%H)"
    ;;
  daily)
    TIMESTAMP="$(date +%Y_%m_%d)"
    ;;
  weekly)
    TIMESTAMP="$(date +%Y_%m_%d)"
    ;;
  monthly)
    TIMESTAMP="$(date +%Y_%m_%d)"
    ;;
  yearly)
    TIMESTAMP="$(date +%Y_%m_%d)"
    ;;
  *)
    log "$ERR_PREFIX: Unknown interval: $INTERVAL"
    (return 1 2>/dev/null) || exit 1
    ;;
esac

# --- Define Paths ---
TMP_BACKUP_DIR="/tmp/iwb-backup-${DATASET}-${INTERVAL}"
mkdir -p "$TMP_BACKUP_DIR"

# These will be set inside the dataset switch:
BACKUP_SOURCE_DIR=""
SQL_DUMP_FILE=""

# --- Dataset Routing ---
case "$DATASET" in
  mail)
    MODULE="BACKUP MAIL"
    BACKUP_SOURCE_DIR="/var/mail"
    ;;

  postfix)
    MODULE="BACKUP POSTIFX"
    BACKUP_SOURCE_DIR="/var/data/backup/postfix"
    mkdir -p "$BACKUP_SOURCE_DIR"
    SQL_DUMP_FILE="${BACKUP_SOURCE_DIR}/${IWB_DOMAIN}_postfixadmin.sql"

    log "Exporting PostfixAdmin database..."
    mysqldump --databases "${IWB_POSTFIXADMIN_SQL_DBNAME}" \
      -u root --socket=/run/mysqld/mysqld.sock \
      -p"${IWB_MYSQL_ROOT_PASSWORD}" > "$SQL_DUMP_FILE"

    ## This was recomended as a better command..???
    # mysqldump --databases "${IWB_POSTFIXADMIN_SQL_DBNAME}" \
    #   --add-drop-database \
    #   --add-drop-table \
    #   --single-transaction \
    #   -u root --socket=/run/mysqld/mysqld.sock \
    #   -p"${IWB_MYSQL_ROOT_PASSWORD}" > "$SQL_DUMP_FILE"

    ;;

  ssl)
    MODULE="BACKUP SSL"
    BACKUP_SOURCE_DIR="/etc/letsencrypt"
    ;;

  dkim)
    MODULE="BACKUP DKIM"
    BACKUP_SOURCE_DIR="/var/lib/rspamd/dkim"
    ;;

  rspamd)
    MODULE="BACKUP RSPAMD"
    BACKUP_SOURCE_DIR="/var/lib/rspamd"
    ;;

  wpdb)
    # MODULE="BACKUP WPDB"
    # BACKUP_SOURCE_DIR="/var/data/backup/wordpress"
    # mkdir -p "$BACKUP_SOURCE_DIR"
    # SQL_DUMP_FILE="${BACKUP_SOURCE_DIR}/${IWB_DOMAIN}_wordpress.sql"

    # log "Exporting WordPress database..."
    # mysqldump --databases "${IWB_WP_MYSQL_DATABASE}" \
    #   -u root --socket=/run/mysqld/mysqld.sock \
    #   -p"${IWB_MYSQL_ROOT_PASSWORD}" > "$SQL_DUMP_FILE"
    # ;;
    MODULE="BACKUP WPDB"
    BACKUP_SOURCE_DIR="/var/data/backup/wordpress"
    mkdir -p "$BACKUP_SOURCE_DIR"
    SQL_DUMP_FILE="${BACKUP_SOURCE_DIR}/${IWB_DOMAIN}_wordpress.sql"

    log "Exporting WordPress database using WP-CLI..."
    wp db export "$SQL_DUMP_FILE" --path="/var/www/html/wordpress" --allow-root
    ;;




  wphtml)
    MODULE="BACKUP WPHTML"
    BACKUP_SOURCE_DIR="/var/www/html"
    ;;

  *)
    log "$ERR_PREFIX: Unknown dataset: $DATASET"
    (return 1 2>/dev/null) || exit 1
    ;;
esac

# --- Archive Creation ---
ARCHIVE_FILENAME="${IWB_DOMAIN}_${DATASET}_${TIMESTAMP}.tar.gz"
ARCHIVE_FILE_PATH="${TMP_BACKUP_DIR}/${ARCHIVE_FILENAME}"

log "Creating backup archive..."
tar -czf "$ARCHIVE_FILE_PATH" -C "$BACKUP_SOURCE_DIR" .

# --- Storj Upload (versioned and latest) ---

REMOTE_KEY_VERSIONED="sj://${IWB_STORJ_WPOPS_BUCKET}/IWBDPP/${DATASET}/${INTERVAL}/${ARCHIVE_FILENAME}"
REMOTE_KEY_LATEST="sj://${IWB_STORJ_WPOPS_BUCKET}/IWBDPP/${DATASET}/latest/${IWB_DOMAIN}_${DATASET}_latest.tar.gz"

log "Uploading backup to Storj (timestamped)..."
storj_upload "$ARCHIVE_FILE_PATH" "$REMOTE_KEY_VERSIONED"

log "Uploading backup to Storj (latest)..."
storj_upload "$ARCHIVE_FILE_PATH" "$REMOTE_KEY_LATEST"

# --- Cleanup ---
#rm -rf "$TMP_BACKUP_DIR"

log "Backup for $DATASET ($INTERVAL) complete."

(return 0 2>/dev/null) || exit 0
