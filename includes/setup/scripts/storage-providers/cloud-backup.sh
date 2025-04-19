#!/bin/bash
# includes/setup/scripts/storage-providers/cloud-backup.sh

## Storj
if [ "$IWB_STORJSETUP" == "true" ]; then
  #Backing up ssl configs to storj and inserting nginx ssl configs
  if [ "$CERTS_RESTORED" = true ] && [ "$DHPARAM_RESTORED" = true ]; then
    # Backing up certificates to Storj
    echo -e "$IWB_PREFIX Backing up certificates to Storj..."
    STAGE_DIR="$CERTBACKUP/stage"
    mkdir -p "$STAGE_DIR/etc/ssl/"
    cp -r /etc/letsencrypt "$STAGE_DIR/etc/letsencrypt"
    cp -r /etc/ssl/dh.pem "$STAGE_DIR/etc/ssl/"

    tar -czf "$CERT_BACKUP_FILE" -C "$STAGE_DIR" etc || {
      echo -e "$IWB_PREFIX $ERR_PREFIX Failed to create certificate archive."
      return 1
    }

    if uplink cp "$CERT_BACKUP_FILE" "sj://${STORJ_WPOPS_BUCKET}/certs/${IWB_DOMAIN}_certs.tar.gz"; then
      echo -e "$IWB_PREFIX ✅ Certificate archive uploaded successfully to Storj."
    else
      echo -e "$IWB_PREFIX $ERR_PREFIX Failed to upload certificate archive."
      return 1
    fi

    # Installing Cronjob for cert renewal
    # I'm doing this here in the case we don't call new certs because we always run this
    echo "$IWB_PREFIX Installing cron job for cert renewal..."
    echo "0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook \"/var/setup/scripts/cert-renew-hook.sh\"" > /etc/crontabs/root
    crond

  else
    echo -e "$IWB_PREFIX $ERR_PREFIX Skipping backup — required components missing (certs or dh.pem)."
  fi
fi
