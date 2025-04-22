#!/bin/bash
# includes/setup/scripts/storage-providers/storage-router.sh

# Setup and verify storage provider Credentials
case "$IWB_PERSISTENT_STORAGE" in
  storj)
    echo -e "${IWB_PREFIX} Storage provider: Storj"
    echo -e "${IWB_PREFIX} Setup and verify Storj Credentials..."
    if ! source /var/setup/scripts/storage-providers/storj/storj-setup.sh; then
      echo -e "$IWB_PREFIX $ERR_PREFIX Storj setup failed. Aborting container startup."
      return 1
    fi
    ;;

  "")
    echo -e "$IWB_PREFIX $ERR_PREFIX No persistent storage backend selected. Aborting."
    return 1
    ;;

  *)
    echo -e "$IWB_PREFIX $ERR_PREFIX Unsupported persistent storage backend: '$IWB_PERSISTENT_STORAGE'"
    return 1
    ;;
esac