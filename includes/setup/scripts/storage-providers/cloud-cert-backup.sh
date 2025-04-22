#!/bin/bash
# includes/setup/scripts/storage-providers/cloud-cert-backup.sh

set -e

# === Expected Env Vars ===
: "${IWB_STORJSETUP:?Must be set to 'true' or 'false'}"
: "${IWB_STORJ_CERT_BACKUP_KEY:?Missing backup key path}"
: "${IWB_DOMAIN:?Missing domain}"

if [ "$IWB_STORJSETUP" == "true" ]; then

  if [ "$CERTS_RESTORED" = true ] && [ "$DHPARAM_RESTORED" = true ]; then
    echo -e "$IWB_PREFIX Backing up certificates to Storj..."

    BACKUP_ROOT="/tmp/cert-backups"
    STAGE_DIR="$BACKUP_ROOT/stage"
    CERT_ARCHIVE_PATH="$BACKUP_ROOT/${IWB_DOMAIN}_certs.tar.gz"

    mkdir -p "$STAGE_DIR/etc/ssl/"
    cp -r /etc/letsencrypt "$STAGE_DIR/etc/letsencrypt"
    cp -r /etc/ssl/dh.pem "$STAGE_DIR/etc/ssl/"

    tar -czf "$CERT_ARCHIVE_PATH" -C "$STAGE_DIR" etc || {
      echo -e "$IWB_PREFIX $ERR_PREFIX Failed to create certificate archive."
      return 1
    }

    if uplink cp "$CERT_ARCHIVE_PATH" "$IWB_STORJ_CERT_BACKUP_KEY"; then
      echo -e "$IWB_PREFIX ✅ Certificate archive uploaded successfully to Storj."
    else
      echo -e "$IWB_PREFIX $ERR_PREFIX Failed to upload certificate archive."
      return 1
    fi

    # === Install certbot renew cronjob ===
    echo "$IWB_PREFIX Installing cron job for cert renewal..."
    echo "0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook \"/var/setup/scripts/cert-renew-hook.sh\"" > /etc/crontabs/root
    crond

  else
    echo -e "$IWB_PREFIX $ERR_PREFIX Skipping backup — required components missing (certs or dh.pem)."
  fi
fi

return 0
