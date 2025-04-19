#!/bin/bash
# includes/setup/scripts/cert-setup.sh

set -euo pipefail

CERTS_RESTORED=false
DHPARAM_RESTORED=false

case "$PERSISTENT_STORAGE" in
  storj)
    # Setup Storj Access
    if [ "$PERSISTENT_STORAGE" == "storj" ]; then
      echo -e "$IWB_PREFIX Initializing Storj backup system..."
      mkdir -p /root/.config/storj/uplink
      cat > /root/.config/storj/uplink/config.ini <<EOF
[analytics]
enabled = false

[metrics]
addr =
EOF
      echo -e "$IWB_PREFIX config.ini written to suppress analytics prompt"

      if uplink access import default "$STORJ_GRANT" --force; then
        uplink access use default
        echo -e "$IWB_PREFIX Storj access imported and set to default"
      else
        echo -e "$IWB_PREFIX $ERR_PREFIX Failed to import Storj access grant"
        exit 1
      fi

    #  echo -e "$IWB_PREFIX DEBUG: Dumping generated access.json"
    #  cat /root/.config/storj/uplink/access.json
    #  uplink version

      echo -e "$IWB_PREFIX Verifying Storj access for bucket: $STORJ_WPOPS_BUCKET"
      if ! uplink ls "sj://${STORJ_WPOPS_BUCKET}/"; then
        echo -e "$IWB_PREFIX $ERR_PREFIX Failed to verify Storj access. Check STORJ_GRANT and STORJ_WPOPS_BUCKET values."
        exit 1
      else
        echo -e "$IWB_PREFIX Storj access verified successfully for bucket: $STORJ_WPOPS_BUCKET"
      fi

    fi

    echo -e "$IWB_PREFIX Checking for existing certificate backup on Storj..."

    CERTBACKUP="/tmp/cert-backups"
    CERT_BACKUP_FILE="$CERTBACKUP/${IWB_DOMAIN}_certs.tar.gz"
    RESTORE_TMP="$CERTBACKUP/unpacked"
    mkdir -p "$CERTBACKUP" "$RESTORE_TMP"
    
    if uplink cp "sj://${STORJ_WPOPS_BUCKET}/certs/${IWB_DOMAIN}_certs.tar.gz" "$CERT_BACKUP_FILE"; then
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

    # Generate dh.pem if missing
    if [ "$DHPARAM_RESTORED" != true ]; then
      echo -e "$IWB_PREFIX Generating dh.pem..."
      mkdir -p /etc/ssl
      openssl dhparam -out /etc/ssl/dh.pem 2048 > /dev/null 2>&1 || {
        echo -e "$IWB_PREFIX $ERR_PREFIX Failed to generate dh.pem."
        return 1
      }
      DHPARAM_RESTORED=true
    fi

    # Request new certs if needed
    if [ "$CERTS_RESTORED" != true ]; then
      echo -e "$IWB_PREFIX Starting temporary Nginx for HTTP-01 challenge..."
      # Setup Nginx virtual host templates for http (initial certbot run)
      echo -e "${IWB_PREFIX} Configuring Nginx site templates..."
      NGINX_TEMPLATE_DIR="/var/setup/configs/http/nginx/sites-available"
      NGINX_TARGET_DIR="/etc/nginx/http.d"
      mkdir -p "$NGINX_TARGET_DIR"

      # Replace {{IWB_DOMAIN}} in each template and symlink into the Nginx directory
      for SITE in default mail webmail; do
        TEMPLATE_FILE="$NGINX_TEMPLATE_DIR/${SITE}.conf.template"
        OUTPUT_FILE="$NGINX_TEMPLATE_DIR/${SITE}.conf"
        TARGET_LINK="$NGINX_TARGET_DIR/${SITE}.conf"

        if [ -f "$TEMPLATE_FILE" ]; then
          sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"
          ln -sf "$OUTPUT_FILE" "$TARGET_LINK"
          echo -e "${IWB_PREFIX} Linked $SITE.conf for $IWB_DOMAIN"
        else
          echo -e "${IWB_PREFIX} ERROR: Missing template: $TEMPLATE_FILE"
        fi
      done

      nginx -g 'daemon off;' &
      NGINX_TEMP_PID=$!

      for i in {1..10}; do
        if netstat -ltn | grep -q ':80'; then
          break
        fi
        sleep 1
        if [ "$i" -eq 10 ]; then
          echo -e "$IWB_PREFIX $ERR_PREFIX Timed out waiting for Nginx to bind to port 80. Aborting."
          kill "$NGINX_TEMP_PID"
          return 1
        fi
      done

      echo -e "$IWB_PREFIX Requesting new certificates via certbot..."
      if certbot certonly --nginx -n --agree-tos --email "$MAIL_USER@${IWB_DOMAIN}" \
        -d "${IWB_DOMAIN}" \
        -d "www.${IWB_DOMAIN}" \
        -d "mail.${IWB_DOMAIN}" \
        -d "webmail.${IWB_DOMAIN}"; then

        echo -e "$IWB_PREFIX Certificate issued successfully."
        CERTS_RESTORED=true
      else
        echo -e "$IWB_PREFIX $ERR_PREFIX Certbot failed to obtain certificates."
        kill "$NGINX_TEMP_PID"
        return 1
      fi

      echo -e "$IWB_PREFIX Stopping temporary Nginx..."
      kill "$NGINX_TEMP_PID"
      sleep 1
    fi
    
    ### Backing up ssl configs to storj and inserting nginx ssl configs
    if [ "$CERTS_RESTORED" = true ] && [ "$DHPARAM_RESTORED" = true ]; then
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

    else
      echo -e "$IWB_PREFIX $ERR_PREFIX Skipping backup — required components missing (certs or dh.pem)."
    fi

    ;;

  "")
    echo -e "$IWB_PREFIX $ERR_PREFIX No persistent storage backend selected. Aborting."
    return 1
    ;;

  *)
    echo -e "$IWB_PREFIX $ERR_PREFIX Unsupported persistent storage backend: '$PERSISTENT_STORAGE'"
    return 1
    ;;
esac

return 0
