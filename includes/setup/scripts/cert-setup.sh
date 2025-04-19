#!/bin/bash
# includes/setup/scripts/cert-setup.sh

set -euo pipefail

CERTS_RESTORED=false
DHPARAM_RESTORED=false

echo -e "${IWB_PREFIX} Attempting to restore from cloud"
if ! source /var/setup/scripts/storage-providers/cloud-restore.sh; then
  echo -e "$IWB_PREFIX $ERR_PREFIX Cloud restore failed -Aborting container startup."
  return 1
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

### Backup certs
echo -e "${IWB_PREFIX} Attempting to backup certs to the cloud"
if ! source /var/setup/scripts/storage-providers/cloud-backup.sh; then
  echo -e "$IWB_PREFIX $ERR_PREFIX Cloud backup failed -Aborting container startup."
  return 1
fi


return 0
