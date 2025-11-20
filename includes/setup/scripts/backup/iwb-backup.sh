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
    mariadb-dump --databases "${IWB_POSTFIXADMIN_SQL_DBNAME}" \
      -u root --socket=/run/mysqld/mysqld.sock \
      -p"${IWB_MYSQL_ROOT_PASSWORD}" > "$SQL_DUMP_FILE"

    ## This was recomended as a better command..???
    # mariadb-dump --databases "${IWB_POSTFIXADMIN_SQL_DBNAME}" \
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
    MODULE="BACKUP WPDB"
    BACKUP_SOURCE_DIR="/var/data/backup/wordpress"
    mkdir -p "$BACKUP_SOURCE_DIR"
    SQL_DUMP_FILE="${BACKUP_SOURCE_DIR}/${IWB_DOMAIN}_wordpress.sql"

    log "Enabling WordPress maintenance mode..."
    wp maintenance-mode activate --path="/var/www/html/wordpress" --allow-root || {
      log "$ERR_PREFIX Failed to enable maintenance mode — continuing anyway."
    }

    log "Exporting WordPress database using WP-CLI..."
    if wp db export "$SQL_DUMP_FILE" --path="/var/www/html/wordpress" --allow-root; then
      log "Database export successful: $SQL_DUMP_FILE"
    else
      log "$ERR_PREFIX WordPress DB export failed."
    fi

    log "Disabling WordPress maintenance mode..."
    wp maintenance-mode deactivate --path="/var/www/html/wordpress" --allow-root || {
      log "$ERR_PREFIX Failed to disable maintenance mode — you may need to manually clear .maintenance"
    }
    ;;

  wphtml)
    MODULE="BACKUP WPHTML"
    BACKUP_SOURCE_DIR="/var/www/html"
    ;;

  n8n)
    MODULE="BACKUP N8N"
    
    # n8n data is stored in /var/www/html/n8n (persistent data directory, not web-served)
    # Set BACKUP_SOURCE_DIR to follow the script's convention
    BACKUP_SOURCE_DIR="/var/www/html/n8n"
    
    log "${MODULE} Backing up n8n SQLite database and user files..."
    
    # Function to check if n8n has active workflow executions
    check_n8n_active_executions() {
      local n8n_url="http://localhost:5678/api/v1/executions"
      local max_wait=300  # 5 minutes max wait
      local wait_time=0
      local check_interval=10
      
      # Check if n8n is responding
      if ! curl -sf "$n8n_url?limit=1" > /dev/null 2>&1; then
        log "${MODULE} n8n API not responding, assuming no active executions"
        return 0
      fi
      
      # Check for running executions
      while [ $wait_time -lt $max_wait ]; do
        local running_count=$(curl -sf "$n8n_url?status=running&limit=100" 2>/dev/null | grep -o '"id":' | wc -l || echo "0")
        
        if [ "$running_count" -eq 0 ]; then
          log "${MODULE} No active workflow executions detected"
          return 0
        else
          log "${MODULE} Found $running_count active workflow execution(s), waiting ${check_interval}s..."
          sleep $check_interval
          wait_time=$((wait_time + check_interval))
        fi
      done
      
      log "$ERR_PREFIX Timeout waiting for workflows to complete after ${max_wait}s. Skipping backup."
      return 1
    }
    
    # Check if supervisord is running and stop n8n for consistent backup
    if pgrep supervisord > /dev/null; then
      # First check if n8n has active executions
      if ! check_n8n_active_executions; then
        log "$ERR_PREFIX Active workflows still running after timeout. Backup cancelled to avoid interruption."
        return 1
      fi
      
      log "${MODULE} Stopping n8n service for consistent backup..."
      supervisorctl stop n8n
      N8N_WAS_RUNNING=true
    else
      log "${MODULE} Supervisord not running, proceeding with backup..."
      N8N_WAS_RUNNING=false
    fi
    
    if [ ! -d "$BACKUP_SOURCE_DIR" ]; then
      log "$ERR_PREFIX No n8n data directory found at $BACKUP_SOURCE_DIR"
    else
      log "${MODULE} Data will be backed up from: $BACKUP_SOURCE_DIR"
      log "${MODULE} Backup includes: database.sqlite, workflows, credentials, license, and all n8n data"
    fi
    
    # Restart n8n service if it was running
    if [ "$N8N_WAS_RUNNING" = true ]; then
      log "${MODULE} Restarting n8n service..."
      supervisorctl start n8n
    fi
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

storj_upload_with_retry() {
    local file="$1"
    local key="$2"
    local attempts=0
    local success=false

    while [ $attempts -lt 3 ]; do
        log "Uploading to Storj (attempt $((attempts + 1))): $key"
        if storj_upload "$file" "$key"; then
            success=true
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    if [ "$success" != true ]; then
        log "ERROR: Failed to upload $key after 3 attempts."
        (return 1 2>/dev/null) || exit 1
    fi
}

storj_upload_with_retry "$ARCHIVE_FILE_PATH" "$REMOTE_KEY_VERSIONED"
storj_upload_with_retry "$ARCHIVE_FILE_PATH" "$REMOTE_KEY_LATEST"


# --- Cleanup ---
#rm -rf "$TMP_BACKUP_DIR"

log "Backup for $DATASET ($INTERVAL) complete."

(return 0 2>/dev/null) || exit 0
