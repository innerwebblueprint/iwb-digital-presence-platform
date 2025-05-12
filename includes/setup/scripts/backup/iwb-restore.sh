#!/bin/bash
# includes/setup/scripts/backup/iwb-restore.sh

# Usage: iwb-restore.sh <dataset> [timestamp]
# Datasets: mail, postfix, ssl, dkim, rspamd, wpdb, wphtml
# Timestamp (optional): e.g., 2025_04_26 or just 0426 (assumes current year)
# If no timestamp is passed, 'latest' will be restored.

# --- Configuration ---
CALL_MODULE=$MODULE
MODULE="$CALL_MODULE RESTORE"

LOG_FILE="/var/log/iwb-restore.log"

# Load environment and functions
source /var/setup/scripts/setup-env.sh
source /var/setup/scripts/storage-providers/storj/storj-functions.sh

# Redirect all output of log function to console and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Input Validation ---
DATASET="$1"
TIMESTAMP="${2:-latest}"


if [ -z "$DATASET" ]; then
  log "$ERR_PREFIX: Usage: $0 <dataset> [timestamp]"
  (return 1 2>/dev/null) || exit 1
fi

YEAR=$(date +%Y)

# Handle TIMESTAMP if partial
# false is empty string $TIMESTAMP
if [ -z "$TIMESTAMP" ] || [ "$TIMESTAMP" = "latest" ]; then
  ARCHIVE_BASENAME="${IWB_DOMAIN}_${DATASET}_latest.tar.gz"
  REMOTE_KEY="sj://${IWB_STORJ_WPOPS_BUCKET}/IWBDPP/${DATASET}/latest/${ARCHIVE_BASENAME}"
else
  if [[ "$TIMESTAMP" =~ ^[0-9]{4}$ ]]; then
    TIMESTAMP="${YEAR}_${TIMESTAMP:0:2}_${TIMESTAMP:2:2}"
  fi
  log "This doesn't actually work at the moment - see restore-issue.md in reference"
  #ARCHIVE_BASENAME="${IWB_DOMAIN}_${DATASET}_${TIMESTAMP}.tar.gz"
  #REMOTE_KEY="sj://${IWB_STORJ_WPOPS_BUCKET}/IWBDPP/${DATASET}/latest/${ARCHIVE_BASENAME}"
  (return 1 2>/dev/null) || exit 1
fi

TMP_RESTORE_DIR="/tmp/iwb-restore-${DATASET}"
mkdir -p "$TMP_RESTORE_DIR"

ARCHIVE_PATH="$TMP_RESTORE_DIR/$ARCHIVE_BASENAME"

# --- Download from Storj ---
log "Attempting to restore [$DATASET]"
log "Restore path: $ARCHIVE_BASENAME ..."

if storj_download "$REMOTE_KEY" "$ARCHIVE_PATH"; then
  log "Download succeeded, proceeding with restore..."
else
  log "$ERR_PREFIX: Failed to download backup from Storj."
  (return 1 2>/dev/null) || exit 1
fi

# if [ ! -f "$ARCHIVE_PATH" ]; then
#   log "$ERR_PREFIX Failed to download archive from Storj: $REMOTE_KEY"
#   (return 1 2>/dev/null) || exit 1
# fi

# --- Extract and Deploy ---
case "$DATASET" in
  mail)
    MODULE="RESTORE MAIL"
    log "Restoring Maildir..."
    tar -xzf "$ARCHIVE_PATH" -C /var/mail
    ;;

  postfix)
    MODULE="RESTORE POSTFIXADMIN"
    log "Restoring PostfixAdmin database..."
    mkdir -p /var/data/backup/postfix
    tar -xzf "$ARCHIVE_PATH" -C /var/data/backup/postfix
    SQL_FILE="/var/data/backup/postfix/${IWB_DOMAIN}_postfixadmin.sql"
    if [ -f "$SQL_FILE" ]; then
      mysql --socket=/run/mysqld/mysqld.sock -u root -p"${IWB_MYSQL_ROOT_PASSWORD}" < "$SQL_FILE"
      log "PostfixAdmin DB restore completed."
    else
      log "$ERR_PREFIX SQL dump not found after extraction."
    fi
    ;;

  ssl)
    MODULE="RESTORE SSL"
    log "Restoring SSL/TLS certificates..."
    mkdir -p /etc/letsencrypt
    tar -xzf "$ARCHIVE_PATH" -C /etc/letsencrypt
    ;;

  dkim)
    MODULE="RESTORE DKIM"
    log "Restoring DKIM signing keys..."
    tar -xzf "$ARCHIVE_PATH" -C "$TMP_RESTORE_DIR"
    tar -xzf "$ARCHIVE_PATH" -C /var/lib/rspamd/dkim
    ;;

  rspamd)
    MODULE="RESTORE RSPAMD"
    log "Restoring Rspamd data..."
    tar -xzf "$ARCHIVE_PATH" -C /var/lib/rspamd
    ;;

  wpdb)
    # MODULE="RESTORE WPDB"
    # log "Restoring WordPress database..."
    # mkdir -p /var/data/backup/wordpress
    # tar -xzf "$ARCHIVE_PATH" -C /var/data/backup/wordpress
    # SQL_FILE="/var/data/backup/wordpress/${IWB_DOMAIN}_wordpress.sql"
    # if [ -f "$SQL_FILE" ]; then
    #   mysql --socket=/run/mysqld/mysqld.sock -u root -p"${IWB_MYSQL_ROOT_PASSWORD}" "${IWB_WORDPRESS_SQL_DBNAME}" < "$SQL_FILE"
    #   log "WordPress DB restore completed."
    # else
    #   log "$ERR_PREFIX SQL dump not found after extraction."
    # fi
    # ;;

    MODULE="RESTORE WPDB"
    log "Restoring WordPress database..."
    mkdir -p /var/data/backup/wordpress
    tar -xzf "$ARCHIVE_PATH" -C /var/data/backup/wordpress

    SQL_FILE="/var/data/backup/wordpress/${IWB_DOMAIN}_wordpress.sql"
    if [ -f "$SQL_FILE" ]; then
      log "Importing SQL using WP-CLI..."
      wp db import "$SQL_FILE" --path="/var/www/html/wordpress" --allow-root
      log "WordPress DB restore completed."
    else
      log "$ERR_PREFIX SQL dump not found after extraction."
    fi
    ;;


  wphtml)
    MODULE="RESTORE WPHTML"
    log "Restoring WordPress files (html)..."
    tar -xzf "$ARCHIVE_PATH" -C /var/www/html
    ;;

  n8n)
    MODULE="RESTORE N8N"
    log "Restoring n8n data directory..."
    mkdir -p /var/www/html/n8n
    tar -xzf "$ARCHIVE_PATH" -C /var/www/html/n8n
    ;;

  *)
    log "$ERR_PREFIX Unknown dataset: $DATASET"
    (return 1 2>/dev/null) || exit 1
    ;;
esac

# --- Cleanup ---
#rm -rf "$TMP_RESTORE_DIR"

log "Restore for $DATASET completed."

MODULE=$CALL_MODULE
(return 0 2>/dev/null) || exit 0
