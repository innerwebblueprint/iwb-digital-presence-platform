#!/bin/bash
# includes/setup/scripts/storage-providers/storage-router.sh


MODULE="STORAGE-ROUTER"

export IWB_STORJSETUP="${IWB_STORJSETUP:-false}"
export IWB_R2SETUP="${IWB_R2SETUP:-false}"
export IWB_STORAGE_ROUTER_INITIALIZED="${IWB_STORAGE_ROUTER_INITIALIZED:-false}"

if [ "$IWB_STORAGE_ROUTER_INITIALIZED" = "true" ]; then
  log "Storage providers already initialized for this startup. Reusing existing setup."
  (return 0 2>/dev/null) || exit 0
fi

if [ -n "${IWB_STORJ_GRANT:-}" ] && [ "${IWB_PERSISTENT_STORAGE}" != "storj" ] && [ "$IWB_STORJSETUP" != "true" ]; then
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
    if [ "$IWB_STORJSETUP" = "true" ]; then
      log "Storage provider: Storj"
      log "Storj credentials already initialized."
    else
      log "Storage provider: Storj"
      log "Setup and verify Storj Credentials..."
      if ! source /var/setup/scripts/storage-providers/storj/storj-setup.sh; then
        log "$ERR_PREFIX Storj setup failed."
        (return 1 2>/dev/null) || exit 1
      fi
    fi
    ;;

  r2)
    if [ "$IWB_R2SETUP" = "true" ]; then
      log "Storage provider: Cloudflare R2"
      log "Cloudflare R2 credentials already initialized."
    else
      log "Storage provider: Cloudflare R2"
      log "Setup and verify Cloudflare R2 credentials..."
      if ! source /var/setup/scripts/storage-providers/r2/r2-setup.sh; then
        log "$ERR_PREFIX Cloudflare R2 setup failed."
        (return 1 2>/dev/null) || exit 1
      fi
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

export IWB_STORAGE_ROUTER_INITIALIZED=true

(return 0 2>/dev/null) || exit 0
