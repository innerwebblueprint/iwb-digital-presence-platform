#!/bin/bash
# includes/setup/scripts/storage-providers/storage-functions.sh
# Provider-neutral storage helpers

storage_provider_name() {
  echo "${IWB_PERSISTENT_STORAGE}"
}

storage_bucket_name() {
  case "${IWB_PERSISTENT_STORAGE}" in
    storj)
      echo "${IWB_STORJ_WPOPS_BUCKET}"
      ;;
    r2)
      echo "${IWB_R2_BUCKET}"
      ;;
    *)
      return 1
      ;;
  esac
}

storage_uri_scheme() {
  case "${IWB_PERSISTENT_STORAGE}" in
    storj) echo "sj" ;;
    r2) echo "s3" ;;
    *) return 1 ;;
  esac
}

storage_uri_for_path() {
  local path="$1"
  local bucket
  local scheme

  bucket="$(storage_bucket_name)" || return 1
  scheme="$(storage_uri_scheme)" || return 1

  path="${path#/}"
  echo "${scheme}://${bucket}/${path}"
}

storage_prefix() {
  local dataset="$1"
  local interval="$2"
  storage_uri_for_path "IWBDPP/${dataset}/${interval}/"
}

storage_key_versioned() {
  local dataset="$1"
  local interval="$2"
  local archive_filename="$3"
  storage_uri_for_path "IWBDPP/${dataset}/${interval}/${archive_filename}"
}

storage_key_latest() {
  local dataset="$1"
  local latest_filename="$2"
  storage_uri_for_path "IWBDPP/${dataset}/latest/${latest_filename}"
}

storage_upload() {
  local local_file="$1"
  local remote_path="$2"

  case "${IWB_PERSISTENT_STORAGE}" in
    storj)
      storj_upload "$local_file" "$remote_path"
      ;;
    r2)
      r2_upload "$local_file" "$remote_path"
      ;;
    *)
      log "$ERR_PREFIX Unsupported storage provider: ${IWB_PERSISTENT_STORAGE}"
      return 1
      ;;
  esac
}

storage_download() {
  local remote_path="$1"
  local local_file="$2"

  case "${IWB_PERSISTENT_STORAGE}" in
    storj)
      storj_download "$remote_path" "$local_file"
      ;;
    r2)
      r2_download "$remote_path" "$local_file"
      ;;
    *)
      log "$ERR_PREFIX Unsupported storage provider: ${IWB_PERSISTENT_STORAGE}"
      return 1
      ;;
  esac
}

storage_list() {
  local prefix="$1"

  case "${IWB_PERSISTENT_STORAGE}" in
    storj)
      storj_list "$prefix"
      ;;
    r2)
      r2_list "$prefix"
      ;;
    *)
      log "$ERR_PREFIX Unsupported storage provider: ${IWB_PERSISTENT_STORAGE}"
      return 1
      ;;
  esac
}

storage_delete() {
  local key="$1"

  case "${IWB_PERSISTENT_STORAGE}" in
    storj)
      storj_delete "$key"
      ;;
    r2)
      r2_delete "$key"
      ;;
    *)
      log "$ERR_PREFIX Unsupported storage provider: ${IWB_PERSISTENT_STORAGE}"
      return 1
      ;;
  esac
}

case "${IWB_PERSISTENT_STORAGE}" in
  storj)
    source /var/setup/scripts/storage-providers/storj/storj-functions.sh
    ;;
  r2)
    source /var/setup/scripts/storage-providers/r2/r2-functions.sh
    ;;
  *)
    log "$ERR_PREFIX Unsupported storage provider: '${IWB_PERSISTENT_STORAGE}'"
    (return 1 2>/dev/null) || exit 1
    ;;
esac

(return 0 2>/dev/null) || exit 0
