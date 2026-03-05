#!/bin/bash
# includes/setup/scripts/storage-providers/migrate-storage.sh

set -euo pipefail

MODULE="STORAGE MIGRATE"
source /var/setup/scripts/setup-env.sh

DATASET="all"
INTERVAL="all"
FROM_PROVIDER=""
TO_PROVIDER=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      FROM_PROVIDER="$2"
      shift 2
      ;;
    --to)
      TO_PROVIDER="$2"
      shift 2
      ;;
    --dataset)
      DATASET="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      log "$ERR_PREFIX Unknown argument: $1"
      (return 1 2>/dev/null) || exit 1
      ;;
  esac
done

if [[ -z "$FROM_PROVIDER" || -z "$TO_PROVIDER" ]]; then
  log "$ERR_PREFIX Usage: $0 --from <storj|r2> --to <storj|r2> [--dataset <name|all>] [--interval <name|all>] [--dry-run]"
  (return 1 2>/dev/null) || exit 1
fi

if [[ "$FROM_PROVIDER" == "$TO_PROVIDER" ]]; then
  log "$ERR_PREFIX Source and destination providers must be different"
  (return 1 2>/dev/null) || exit 1
fi

VALID_DATASETS=(mail postfix ssl dkim rspamd wpdb wphtml n8n akash)
VALID_INTERVALS=(snapshot hourly daily weekly monthly yearly)

if [[ "$DATASET" == "all" ]]; then
  TARGET_DATASETS=("${VALID_DATASETS[@]}")
else
  TARGET_DATASETS=("$DATASET")
fi

if [[ "$INTERVAL" == "all" ]]; then
  TARGET_INTERVALS=("${VALID_INTERVALS[@]}")
else
  TARGET_INTERVALS=("$INTERVAL")
fi

state_file="/var/data/state/storage-migration-${FROM_PROVIDER}-to-${TO_PROVIDER}.state"
mkdir -p "$(dirname "$state_file")"
touch "$state_file"

storj_bucket_uri() {
  local path="$1"
  path="${path#/}"
  echo "sj://${IWB_STORJ_WPOPS_BUCKET}/${path}"
}

r2_bucket_uri() {
  local path="$1"
  path="${path#/}"
  echo "s3://${IWB_R2_BUCKET}/${path}"
}

r2_aws() {
  AWS_ACCESS_KEY_ID="${IWB_R2_ACCESS_KEY_ID}" \
  AWS_SECRET_ACCESS_KEY="${IWB_R2_SECRET_ACCESS_KEY}" \
  AWS_DEFAULT_REGION="${IWB_R2_REGION:-auto}" \
  aws --endpoint-url "https://${IWB_R2_ACCOUNT_ID}.r2.cloudflarestorage.com" "$@"
}

provider_list() {
  local provider="$1"
  local prefix_path="$2"

  case "$provider" in
    storj)
      local prefix_uri
      prefix_uri="$(storj_bucket_uri "$prefix_path")"
      uplink ls "$prefix_uri" | awk '/\.tar\.gz$/ {print $NF}' | while read -r obj; do
        if [[ "$obj" == sj://* ]]; then
          echo "$obj"
        elif [[ -n "$obj" ]]; then
          echo "${prefix_uri}${obj}"
        fi
      done
      ;;
    r2)
      local prefix_uri
      prefix_uri="$(r2_bucket_uri "$prefix_path")"
      r2_aws s3 ls "$prefix_uri" | awk '/\.tar\.gz$/ {print $NF}' | while read -r key; do
        if [[ -z "$key" ]]; then
          continue
        fi
        if [[ "$key" == IWBDPP/* ]]; then
          echo "s3://${IWB_R2_BUCKET}/${key}"
        else
          echo "$(r2_bucket_uri "${prefix_path}${key}")"
        fi
      done
      ;;
    *)
      return 1
      ;;
  esac
}

provider_download() {
  local provider="$1"
  local remote_uri="$2"
  local local_path="$3"

  case "$provider" in
    storj)
      uplink cp "$remote_uri" "$local_path" >/dev/null 2>&1
      ;;
    r2)
      r2_aws s3 cp "$remote_uri" "$local_path" --only-show-errors >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

provider_upload() {
  local provider="$1"
  local local_path="$2"
  local remote_uri="$3"

  case "$provider" in
    storj)
      uplink cp "$local_path" "$remote_uri" >/dev/null 2>&1
      ;;
    r2)
      r2_aws s3 cp "$local_path" "$remote_uri" --only-show-errors >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

build_dest_uri() {
  local provider="$1"
  local relative_path="$2"

  case "$provider" in
    storj) storj_bucket_uri "$relative_path" ;;
    r2) r2_bucket_uri "$relative_path" ;;
    *) return 1 ;;
  esac
}

relative_object_path() {
  local uri="$1"
  case "$uri" in
    sj://*) echo "${uri#sj://${IWB_STORJ_WPOPS_BUCKET}/}" ;;
    s3://*) echo "${uri#s3://${IWB_R2_BUCKET}/}" ;;
    *) return 1 ;;
  esac
}

validate_provider_env() {
  local provider="$1"
  case "$provider" in
    storj)
      : "${IWB_STORJ_GRANT:?IWB_STORJ_GRANT not set}"
      : "${IWB_STORJ_WPOPS_BUCKET:?IWB_STORJ_WPOPS_BUCKET not set}"
      uplink access import migration "${IWB_STORJ_GRANT}" --force >/dev/null 2>&1 || true
      uplink access use migration >/dev/null 2>&1 || true
      ;;
    r2)
      : "${IWB_R2_ACCOUNT_ID:?IWB_R2_ACCOUNT_ID not set}"
      : "${IWB_R2_ACCESS_KEY_ID:?IWB_R2_ACCESS_KEY_ID not set}"
      : "${IWB_R2_SECRET_ACCESS_KEY:?IWB_R2_SECRET_ACCESS_KEY not set}"
      : "${IWB_R2_BUCKET:?IWB_R2_BUCKET not set}"
      r2_aws s3 ls "s3://${IWB_R2_BUCKET}" >/dev/null 2>&1
      ;;
    *)
      log "$ERR_PREFIX Unsupported provider: ${provider}"
      (return 1 2>/dev/null) || exit 1
      ;;
  esac
}

log "Validating source and destination provider credentials..."
validate_provider_env "$FROM_PROVIDER"
validate_provider_env "$TO_PROVIDER"

tmp_dir="/tmp/iwb-storage-migration"
mkdir -p "$tmp_dir"

migrated=0
skipped=0
failed=0

for ds in "${TARGET_DATASETS[@]}"; do
  for itv in "${TARGET_INTERVALS[@]}"; do
    versioned_prefix="IWBDPP/${ds}/${itv}/"
    log "Scanning ${FROM_PROVIDER} prefix: ${versioned_prefix}"

    while IFS= read -r src_uri; do
      [[ -z "$src_uri" ]] && continue

      rel_path="$(relative_object_path "$src_uri")"
      state_key="${FROM_PROVIDER}|${TO_PROVIDER}|${rel_path}"

      if grep -Fxq "$state_key" "$state_file"; then
        skipped=$((skipped + 1))
        continue
      fi

      dst_uri="$(build_dest_uri "$TO_PROVIDER" "$rel_path")"
      obj_file="$tmp_dir/$(basename "$rel_path")"
      verify_file="${obj_file}.verify"

      if $DRY_RUN; then
        log "DRY-RUN ${src_uri} -> ${dst_uri}"
        continue
      fi

      rm -f "$obj_file" "$verify_file"

      if ! provider_download "$FROM_PROVIDER" "$src_uri" "$obj_file"; then
        log "$ERR_PREFIX Download failed: ${src_uri}"
        failed=$((failed + 1))
        continue
      fi

      if ! provider_upload "$TO_PROVIDER" "$obj_file" "$dst_uri"; then
        log "$ERR_PREFIX Upload failed: ${dst_uri}"
        failed=$((failed + 1))
        rm -f "$obj_file"
        continue
      fi

      if ! provider_download "$TO_PROVIDER" "$dst_uri" "$verify_file"; then
        log "$ERR_PREFIX Verification download failed: ${dst_uri}"
        failed=$((failed + 1))
        rm -f "$obj_file" "$verify_file"
        continue
      fi

      src_size=$(stat -c%s "$obj_file")
      dst_size=$(stat -c%s "$verify_file")

      if [[ "$src_size" -ne "$dst_size" ]]; then
        log "$ERR_PREFIX Size verification failed for ${dst_uri} (${src_size} != ${dst_size})"
        failed=$((failed + 1))
      else
        echo "$state_key" >> "$state_file"
        migrated=$((migrated + 1))
        log "Migrated ${rel_path}"
      fi

      rm -f "$obj_file" "$verify_file"
    done < <(provider_list "$FROM_PROVIDER" "$versioned_prefix")

    latest_prefix="IWBDPP/${ds}/latest/"
    log "Scanning ${FROM_PROVIDER} prefix: ${latest_prefix}"

    while IFS= read -r src_uri; do
      [[ -z "$src_uri" ]] && continue

      rel_path="$(relative_object_path "$src_uri")"
      state_key="${FROM_PROVIDER}|${TO_PROVIDER}|${rel_path}"

      if grep -Fxq "$state_key" "$state_file"; then
        skipped=$((skipped + 1))
        continue
      fi

      dst_uri="$(build_dest_uri "$TO_PROVIDER" "$rel_path")"
      obj_file="$tmp_dir/$(basename "$rel_path")"
      verify_file="${obj_file}.verify"

      if $DRY_RUN; then
        log "DRY-RUN ${src_uri} -> ${dst_uri}"
        continue
      fi

      rm -f "$obj_file" "$verify_file"

      if ! provider_download "$FROM_PROVIDER" "$src_uri" "$obj_file"; then
        log "$ERR_PREFIX Download failed: ${src_uri}"
        failed=$((failed + 1))
        continue
      fi

      if ! provider_upload "$TO_PROVIDER" "$obj_file" "$dst_uri"; then
        log "$ERR_PREFIX Upload failed: ${dst_uri}"
        failed=$((failed + 1))
        rm -f "$obj_file"
        continue
      fi

      if ! provider_download "$TO_PROVIDER" "$dst_uri" "$verify_file"; then
        log "$ERR_PREFIX Verification download failed: ${dst_uri}"
        failed=$((failed + 1))
        rm -f "$obj_file" "$verify_file"
        continue
      fi

      src_size=$(stat -c%s "$obj_file")
      dst_size=$(stat -c%s "$verify_file")

      if [[ "$src_size" -ne "$dst_size" ]]; then
        log "$ERR_PREFIX Size verification failed for ${dst_uri} (${src_size} != ${dst_size})"
        failed=$((failed + 1))
      else
        echo "$state_key" >> "$state_file"
        migrated=$((migrated + 1))
        log "Migrated ${rel_path}"
      fi

      rm -f "$obj_file" "$verify_file"
    done < <(provider_list "$FROM_PROVIDER" "$latest_prefix")
  done
done

log "Migration summary: migrated=${migrated}, skipped=${skipped}, failed=${failed}, state=${state_file}"

if [[ "$failed" -gt 0 ]]; then
  (return 1 2>/dev/null) || exit 1
fi

(return 0 2>/dev/null) || exit 0
