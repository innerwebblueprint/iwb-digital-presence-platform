#!/bin/bash
# includes/setup/scripts/storage-providers/r2/r2-functions.sh

r2_aws() {
  AWS_ACCESS_KEY_ID="${IWB_R2_ACCESS_KEY_ID}" \
  AWS_SECRET_ACCESS_KEY="${IWB_R2_SECRET_ACCESS_KEY}" \
  AWS_DEFAULT_REGION="${IWB_R2_REGION:-auto}" \
  aws --endpoint-url "https://${IWB_R2_ACCOUNT_ID}.r2.cloudflarestorage.com" "$@"
}

r2_upload() {
  local local_file="$1"
  local remote_path="$2"

  if [[ -z "$local_file" || -z "$remote_path" ]]; then
    echo "[R2] ERROR: Missing arguments to r2_upload. Usage: r2_upload <local_file_path> <remote_bucket_key>"
    return 1
  fi

  if [[ ! -f "$local_file" ]]; then
    echo "[R2] ERROR: Local file not found: $local_file"
    return 2
  fi

  echo "[R2] Uploading $local_file to $remote_path..."
  if r2_aws s3 cp "$local_file" "$remote_path" --only-show-errors; then
    echo "[R2] Upload successful."
    return 0
  fi

  echo "[R2] ERROR: Upload failed."
  return 3
}

r2_download() {
  local remote_path="$1"
  local local_file="$2"

  log "R2 Attempting to download ${remote_path}"
  log "R2 to ${local_file}..."

  local max_attempts=3
  local attempt_num=1
  local success=false

  while [ "$attempt_num" -le "$max_attempts" ]; do
    if r2_aws s3 cp "$remote_path" "$local_file" --only-show-errors >/dev/null 2>&1; then
      success=true
      break
    fi
    log "R2 Attempt ${attempt_num} failed. Retrying..."
    sleep 2
    attempt_num=$((attempt_num + 1))
  done

  if [ "$success" = true ]; then
    log "R2 Download successful..."
    return 0
  fi

  log "R2 WARN Failed to download ${remote_path} after ${max_attempts} attempts."
  log "R2 WARN It is possible there is no backup file to restore"
  return 1
}

r2_list() {
  local prefix="$1"
  r2_aws s3 ls "$prefix" | awk '/\.tar\.gz$/ {print $NF}'
}

r2_delete() {
  local key="$1"
  r2_aws s3 rm "$key" --only-show-errors
}
