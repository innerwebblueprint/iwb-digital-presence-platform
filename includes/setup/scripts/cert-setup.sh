#!/bin/bash
# includes/setup/scripts/cert-setup.sh

set -euo pipefail
MODULE="SSL"
CERTS_RESTORED=false
DHPARAM_RESTORED=false

log "Attempting to restore certs from cloud"

if ! /var/setup/scripts/backup/iwb-restore.sh ssl; then
  log "$ERR_PREFIX Cloud cert restore failed — Will attempt new cert creation."
  ### This is where we should call a new script 'ssl-new.sh' or something liek that. 
  log "This is where we should call a new script 'ssl-new.sh' or something liek that."
  
  ### DEBUG == Position b01 - Holding container open for debug..."
  echo "$ERR_PREFIX  DEBUG == Position b01 - Holding container open for debug..."
  tail -f /dev/null
  
  (return 1 2>/dev/null) || exit 1

else
  CERTS_RESTORED=true
  DHPARAM_RESTORED=true
fi

### DEPRICATED - TO REMOVE
### We are now using the params from let's encrypt at /etc/letsencrypt/ssl-dhparams.pem
# # === Generate dh.pem if needed ===
# if [ "$DHPARAM_RESTORED" != true ]; then
#   echo -e "$IWB_PREFIX Generating dh.pem..."
#   mkdir -p /etc/ssl
#   openssl dhparam -out /etc/ssl/dh.pem 2048 > /dev/null 2>&1 || {
#     echo -e "$IWB_PREFIX $ERR_PREFIX Failed to generate dh.pem."
#     return 1
#   }
#   DHPARAM_RESTORED=true
# fi

# === Request certificates if needed ===
if [ "$CERTS_RESTORED" != true ]; then
  echo -e "$IWB_PREFIX Starting temporary Nginx for HTTP-01 challenge..."

  echo -e "${IWB_PREFIX} Configuring Nginx site templates..."
  mkdir -p "$IWB_NGINX_CONF_DIR"

  for SITE in default mail webmail; do
    TEMPLATE_FILE="$IWB_SSL_TEMPLATE_DIR/${SITE}.conf.template"
    OUTPUT_FILE="$IWB_SSL_TEMPLATE_DIR/${SITE}.conf"
    TARGET_LINK="$IWB_NGINX_CONF_DIR/${SITE}.conf"

    if [ -f "$TEMPLATE_FILE" ]; then
      sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"
      ln -sf "$OUTPUT_FILE" "$TARGET_LINK"
      echo -e "${IWB_PREFIX} Linked $SITE.conf for $IWB_DOMAIN"
    else
      echo -e "${IWB_PREFIX} $ERR_PREFIX Missing template: $TEMPLATE_FILE"
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

  if certbot certonly --nginx -n --agree-tos \
      --email "$IWB_MAIL_USER@$IWB_DOMAIN" \
      -d "$IWB_DOMAIN" \
      -d "www.$IWB_DOMAIN" \
      -d "mail.$IWB_DOMAIN" \
      -d "webmail.$IWB_DOMAIN"; then
    echo -e "$IWB_PREFIX Certificate issued successfully."
    CERTS_RESTORED=new
  else
    echo -e "$IWB_PREFIX $ERR_PREFIX Certbot failed to obtain certificates."
    kill "$NGINX_TEMP_PID"
    return 1
  fi

  echo -e "$IWB_PREFIX Stopping temporary Nginx..."
  kill "$NGINX_TEMP_PID"
  sleep 1
fi

# === Backup to cloud ===
if [ "$CERTS_RESTORED" = "new" ]; then
  log "Attempting to backup new certs to the cloud..."
  if ! "$IWB_SCRIPTSDIR/backup/iwb-backup.sh" ssl snapshot; then
    echo -e "$IWB_PREFIX $ERR_PREFIX Cloud backup failed — Aborting container startup."
    return 1
  fi
fi


(return 0 2>/dev/null) || exit 0
