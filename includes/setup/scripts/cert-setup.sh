#!/bin/bash
# /var/setup/scripts/cert-setup.sh

set -euo pipefail

case "$PERSISTENT_STORAGE" in
  storj)
    echo -e "$IWB_PREFIX Checking for existing certificate backup on Storj..."
    mkdir -p /tmp/cert-restore

    CERT_BACKUP_FILE="/tmp/cert-restore/${IWB_DOMAIN}_certs.tar.gz"
    if uplink cp "sj://${STORJ_WPOPS_BUCKET}/certs/${IWB_DOMAIN}_certs.tar.gz" "$CERT_BACKUP_FILE"; then
      echo -e "$IWB_PREFIX Found backup. Restoring certificates..."
      tar -xzf "$CERT_BACKUP_FILE" -C / || {
        echo -e "$IWB_PREFIX $ERR_PREFIX Failed to extract certificate archive."
        exit 1
      }
      CERTS_RESTORED=true
    else
      echo -e "$IWB_PREFIX No cert backup found. Will issue new certificates."
      CERTS_RESTORED=false
    fi

    if [ "$CERTS_RESTORED" != true ]; then
      echo -e "$IWB_PREFIX Starting temporary Nginx for HTTP-01 challenge..."
      nginx -g 'daemon off;' &
      NGINX_TEMP_PID=$!

      # Wait until nginx is listening on port 80
      for i in {1..10}; do
        if netstat -ltn | grep -q ':80'; then
          break
        fi
        sleep 1
        if [ "$i" -eq 10 ]; then
          echo -e "$IWB_PREFIX $ERR_PREFIX Timed out waiting for Nginx to bind to port 80. Aborting."
          kill "$NGINX_TEMP_PID"
          exit 1
        fi
      done

      echo -e "$IWB_PREFIX Requesting new certificates via certbot..."
      if certbot certonly --nginx -n --agree-tos --email "$MAIL_USER@${IWB_DOMAIN}" \
        -d "${IWB_DOMAIN}" \
        -d "www.${IWB_DOMAIN}" \
        -d "mail.${IWB_DOMAIN}" \
        -d "webmail.${IWB_DOMAIN}"; then

        echo -e "$IWB_PREFIX Certificate issued successfully."

        echo -e "$IWB_PREFIX Backing up certificates to Storj..."
        mkdir -p /tmp/cert-backups
        
        ARCHIVE_PATH="/tmp/cert-backups/${IWB_DOMAIN}_certs.tar.gz"

        tar -czf "$ARCHIVE_PATH" \
          -C /etc/letsencrypt \
          "live/$IWB_DOMAIN" \
          "archive/$IWB_DOMAIN" \
          "renewal/$IWB_DOMAIN.conf" || {
            echo -e "$IWB_PREFIX $ERR_PREFIX Failed to create certificate archive."
            exit 1
        }


      uplink cp "$ARCHIVE_PATH" "sj://${STORJ_WPOPS_BUCKET}/certs/${IWB_DOMAIN}_certs.tar.gz" || {
        echo -e "$IWB_PREFIX $ERR_PREFIX Failed to upload cert archive to Storj."
      }
      else
        echo -e "$IWB_PREFIX $ERR_PREFIX Certbot failed to obtain certificates."
        kill "$NGINX_TEMP_PID"
        exit 1
      fi

      echo -e "$IWB_PREFIX Stopping temporary Nginx..."
      kill "$NGINX_TEMP_PID"
      sleep 1
    fi
    ;;

  "")
    echo -e "$IWB_PREFIX $ERR_PREFIX No persistent storage backend selected. Aborting."
    exit 1
    ;;

  *)
    echo -e "$IWB_PREFIX $ERR_PREFIX Unsupported persistent storage backend: '$PERSISTENT_STORAGE'"
    exit 1
    ;;
esac

# Safe exit/return mechanism
(return 0 2>/dev/null) || exit 0

