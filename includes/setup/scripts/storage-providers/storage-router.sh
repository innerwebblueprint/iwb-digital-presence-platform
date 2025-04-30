#!/bin/bash
# includes/setup/scripts/storage-providers/storage-router.sh


MODULE="STORAGE-ROUTER"

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