#!/bin/bash
# includes/setup/scripts/backup/iwb-backup-cleanup.sh
# Prunes old Storj backup archives per dataset/interval based on retention policy.
# Usage:
#   iwb-backup-cleanup.sh <dataset|all> <interval|all> [--dry-run]
# Datasets: mail, postfix, ssl, dkim, rspamd, wpdb, wphtml, n8n
# Intervals: snapshot, hourly, daily, weekly, monthly, yearly
# Notes:
# - Operates ONLY on versioned paths: sj://$IWB_STORJ_WPOPS_BUCKET/IWBDPP/<dataset>/<interval>/
# - Never touches latest folder: sj://.../<dataset>/latest/
# - Hourly: intentionally cycles names; cleanup is skipped (max ~24 keys by design)

MODULE="BACKUP CLEANUP"
LOG_FILE="/var/log/iwb-backup-cleanup.log"

# Load environment and storage provider
source /var/setup/scripts/setup-env.sh
source /var/setup/scripts/storage-providers/storage-router.sh
source /var/setup/scripts/storage-providers/storage-functions.sh

# Redirect all output to log
exec > >(tee -a "$LOG_FILE") 2>&1

DATASET="$1"
INTERVAL="$2"
DRY_RUN=false
if [[ "$3" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Validate inputs
VALID_DATASETS=(mail postfix ssl dkim rspamd wpdb wphtml n8n)
VALID_INTERVALS=(snapshot hourly daily weekly monthly yearly)

if [[ -z "$DATASET" || -z "$INTERVAL" ]]; then
  log "$ERR_PREFIX Usage: $0 <dataset|all> <interval|all> [--dry-run]"
  (return 1 2>/dev/null) || exit 1
fi

# Build target lists
TARGET_DATASETS=()
TARGET_INTERVALS=()

if [[ "$DATASET" == "all" ]]; then
  TARGET_DATASETS=("${VALID_DATASETS[@]}")
else
  # ensure dataset valid
  for d in "${VALID_DATASETS[@]}"; do
    if [[ "$d" == "$DATASET" ]]; then TARGET_DATASETS=("$DATASET"); fi
  done
  if [[ ${#TARGET_DATASETS[@]} -eq 0 ]]; then
    log "$ERR_PREFIX Unknown dataset: $DATASET"
    (return 1 2>/dev/null) || exit 1
  fi
fi

if [[ "$INTERVAL" == "all" ]]; then
  TARGET_INTERVALS=("${VALID_INTERVALS[@]}")
else
  for i in "${VALID_INTERVALS[@]}"; do
    if [[ "$i" == "$INTERVAL" ]]; then TARGET_INTERVALS=("$INTERVAL"); fi
  done
  if [[ ${#TARGET_INTERVALS[@]} -eq 0 ]]; then
    log "$ERR_PREFIX Unknown interval: $INTERVAL"
    (return 1 2>/dev/null) || exit 1
  fi
fi

# Retention policy
# Default counts per interval; can be overridden via env e.g. IWB_RETENTION_DAILY=10
RETENTION_SNAPSHOT=${IWB_RETENTION_SNAPSHOT:-5}
RETENTION_HOURLY=${IWB_RETENTION_HOURLY:-24}
RETENTION_DAILY=${IWB_RETENTION_DAILY:-7}
RETENTION_WEEKLY=${IWB_RETENTION_WEEKLY:-4}
RETENTION_MONTHLY=${IWB_RETENTION_MONTHLY:-12}
RETENTION_YEARLY=${IWB_RETENTION_YEARLY:-10}

keep_for_interval() {
  case "$1" in
    snapshot) echo "$RETENTION_SNAPSHOT" ;;
    hourly)   echo "$RETENTION_HOURLY" ;;
    daily)    echo "$RETENTION_DAILY" ;;
    weekly)   echo "$RETENTION_WEEKLY" ;;
    monthly)  echo "$RETENTION_MONTHLY" ;;
    yearly)   echo "$RETENTION_YEARLY" ;;
    *)        echo 0 ;;
  esac
}

# List objects in a prefix. Returns newline-separated object names (no path)
list_objects() {
  local prefix="$1"
  storage_list "$prefix" | while read -r obj; do
    [[ -n "$obj" ]] && echo "${obj##*/}"
  done
}

# Sort objects by name ascending (YYYY_MM_DD sorts correctly lexicographically)
# For hourly, names are HH and cycle; we skip cleanup.

# Delete an object by full key
delete_object() {
  local key="$1"
  if $DRY_RUN; then
    log "DRY-RUN Would delete: $key"
    return 0
  fi
  if storage_delete "$key"; then
    log "Deleted: $key"
    return 0
  else
    log "$ERR_PREFIX Failed to delete: $key"
    return 1
  fi
}

errors=0

for ds in "${TARGET_DATASETS[@]}"; do
  for itv in "${TARGET_INTERVALS[@]}"; do
    local_prefix="$(storage_prefix "$ds" "$itv")"

    # Skip hourly by design (rotation via overwrites)
    if [[ "$itv" == "hourly" ]]; then
      log "${MODULE} Skipping hourly cleanup for ${ds} (managed by overwrite rotation)"
      continue
    fi

    keep_count=$(keep_for_interval "$itv")
    log "${MODULE} Cleanup target: dataset=${ds} interval=${itv} keep=${keep_count}"

    # Gather object names
    mapfile -t objs < <(list_objects "$local_prefix")
    total=${#objs[@]}

    if [[ "$total" -le "$keep_count" ]]; then
      log "${MODULE} Nothing to prune (${total} <= keep ${keep_count}) at ${local_prefix}"
      continue
    fi

    # Sort by name and select oldest extras
    # name example: <domain>_<dataset>_YYYY_MM_DD.tar.gz (lexicographic works)
    IFS=$'\n' sorted=($(printf '%s\n' "${objs[@]}" | sort))
    prune_count=$(( total - keep_count ))
    to_delete=("${sorted[@]:0:prune_count}")

    log "${MODULE} Will prune ${prune_count} of ${total} objects at ${local_prefix}"
    for name in "${to_delete[@]}"; do
      full_key="${local_prefix}${name}"
      delete_object "$full_key" || errors=$((errors+1))
    done
  done
done

if [[ "$errors" -gt 0 ]]; then
  log "$ERR_PREFIX Cleanup completed with $errors error(s)."
  (return 1 2>/dev/null) || exit 1
fi

log "${MODULE} Cleanup completed successfully."
(return 0 2>/dev/null) || exit 0
