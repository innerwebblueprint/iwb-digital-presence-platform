#!/bin/bash
# includes/setup/scripts/storage-providers/cloud-restore.sh

case "$IWB_PERSISTENT_STORAGE" in
  storj)
    ## Validate Storj setup is complete
    if [ "$IWB_STORJSETUP" == "false" ]; then
      if ! source /var/setup/scripts/storage-providers/storj/storj-setup.sh; then
          echo -e "$IWB_PREFIX $ERR_PREFIX Storj setup failed. Aborting container startup."
          return 1
      fi
    fi
    
    echo -e "$IWB_PREFIX Checking for existing certificate backup on Storj..."
    CERTBACKUP="$IWB_CERT_BACKUP_DIR"
    CERT_BACKUP_FILE="$CERTBACKUP/${IWB_DOMAIN}_certs.tar.gz"
    RESTORE_TMP="$CERTBACKUP/unpacked"
    mkdir -p "$CERTBACKUP" "$RESTORE_TMP"
    
    if uplink cp "$IWB_STORJ_CERT_BACKUP_KEY" "$CERT_BACKUP_FILE"; then
      echo -e "$IWB_PREFIX Found backup. Extracting..."

      if tar -xzf "$CERT_BACKUP_FILE" -C "$RESTORE_TMP"; then
        echo -e "$IWB_PREFIX Archive extracted. Checking contents..."

        # Check for certbot files
        if [ -f "$RESTORE_TMP/etc/letsencrypt/renewal/$IWB_DOMAIN.conf" ] && \
           [ -d "$RESTORE_TMP/etc/letsencrypt/live/$IWB_DOMAIN" ] && \
           [ -d "$RESTORE_TMP/etc/letsencrypt/archive/$IWB_DOMAIN" ]; then
          mkdir -p /etc/letsencrypt
          cp -r "$RESTORE_TMP/etc/letsencrypt/"* /etc/letsencrypt/
          echo -e "$IWB_PREFIX Certbot certificates restored."
          CERTS_RESTORED=true
        else
          echo -e "$IWB_PREFIX $ERR_PREFIX Certificate components incomplete."
        fi

        # Restore dh.pem
        if [ -f "$RESTORE_TMP/etc/ssl/dh.pem" ]; then
          mkdir -p /etc/ssl
          cp "$RESTORE_TMP/etc/ssl/dh.pem" /etc/ssl/dh.pem
          echo -e "$IWB_PREFIX dh.pem restored."
          DHPARAM_RESTORED=true
        else
          echo -e "$IWB_PREFIX $ERR_PREFIX dh.pem not found in backup."
        fi

      else
        echo -e "$IWB_PREFIX $ERR_PREFIX Failed to extract certificate archive."
      fi

    else
      echo -e "$IWB_PREFIX No cert backup found. Will issue new certificates."
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

echo -e "$IWB_PREFIX All certs and dh.pem restored from cloud successfully."
return 0
