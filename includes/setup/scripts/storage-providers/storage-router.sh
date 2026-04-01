#!/bin/bash
# includes/setup/scripts/storage-providers/storage-router.sh


MODULE="STORAGE-ROUTER"

if [ -n "${IWB_STORJ_GRANT:-}" ] && [ "${IWB_PERSISTENT_STORAGE}" != "storj" ]; then
  log "Storj credentials detected in environment."
  log "Setting up optional Storj access for root and n8n users..."
  if ! source /var/setup/scripts/storage-providers/storj/storj-setup.sh; then
    log "$ERR_PREFIX Optional Storj access setup failed."
    (return 1 2>/dev/null) || exit 1
  fi
fi

# Setup and verify storage provider Credentials
case "$IWB_PERSISTENT_STORAGE" in
  storj)
    log "Storage provider: Storj"
    log "Setup and verify Storj Credentials..."
    if ! source /var/setup/scripts/storage-providers/storj/storj-setup.sh; then
      log "$ERR_PREFIX Storj setup failed."
      (return 1 2>/dev/null) || exit 1
    fi
    ;;

  r2)
    log "Storage provider: Cloudflare R2"
    log "Setup and verify Cloudflare R2 credentials..."
    if ! source /var/setup/scripts/storage-providers/r2/r2-setup.sh; then
      log "$ERR_PREFIX Cloudflare R2 setup failed."
      (return 1 2>/dev/null) || exit 1
    fi
    ;;

  "")
    echo -e "$IWB_PREFIX $ERR_PREFIX No persistent storage backend selected. Aborting."
    (return 1 2>/dev/null) || exit 1
    ;;

  *)
    echo -e "$IWB_PREFIX $ERR_PREFIX Unsupported persistent storage backend: '$IWB_PERSISTENT_STORAGE'"
    (return 1 2>/dev/null) || exit 1
    ;;
esac

(return 0 2>/dev/null) || exit 0
