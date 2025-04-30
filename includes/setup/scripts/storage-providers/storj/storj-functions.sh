#!/bin/bash
# includes/setup/scripts/storage-providers/storj/storj-functions.sh
# Shared functions for uploading backups to Storj

# Usage:
#   storj_upload <local_file_path> <remote_bucket_key>
#
# Example:
#   storj_upload "/tmp/postfixadmin-snapshot.tar.gz" "sj://mybucket/backups/postfix/snapshot.tar.gz"

storj_upload() {
  local LOCAL_FILE="$1"
  local REMOTE_PATH="$2"

  if [[ -z "$LOCAL_FILE" || -z "$REMOTE_PATH" ]]; then
    echo "[STORJ] ERROR: Missing arguments to storj_upload. Usage: storj_upload <local_file_path> <remote_bucket_key>"
    return 1
  fi

  if [[ ! -f "$LOCAL_FILE" ]]; then
    echo "[STORJ] ERROR: Local file not found: $LOCAL_FILE"
    return 2
  fi

  echo "[STORJ] Uploading $LOCAL_FILE to $REMOTE_PATH..."
  if uplink cp "$LOCAL_FILE" "$REMOTE_PATH"; then
    echo "[STORJ] Upload successful."
    return 0
  else
    echo "[STORJ] ERROR: Upload failed."
    return 3
  fi
}

storj_download() {
  local BACKUP_KEY="$1"
  local LOCAL_FILE="$2"

  log "STORJ Attempting to download $BACKUP_KEY"
  log "STORJ to $LOCAL_FILE..."

max_attempts=3
attempt_num=1
success=false

while [ $attempt_num -le $max_attempts ]; do
  if uplink cp "$BACKUP_KEY" "$LOCAL_FILE" >/dev/null 2>&1; then
    success=true
    break
  else
    log "STORJ Attempt $attempt_num failed. Retrying..."
    sleep 2
    attempt_num=$(( attempt_num + 1 ))
  fi
done

if [ "$success" = true ]; then
  log "STORJ Download successful..."
  return 0
else
  log "STORJ WARN Failed to download $BACKUP_KEY after $max_attempts attempts."
  log "STORJ WARN It is possible there is no backup file to restore"
  return 1
fi
}

# End of storj-functions.sh
