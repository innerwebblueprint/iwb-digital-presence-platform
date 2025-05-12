#!/bin/bash
# includes/setup/scripts/setup-sslcerts.sh

set -euo pipefail
MODULE="SSL"
CERTS_RESTORED=false
DHPARAM_RESTORED=false

IWB_SSL_DOMAINS=(
  "$IWB_DOMAIN"
  "www.$IWB_DOMAIN"
  "mail.$IWB_DOMAIN"
  "webmail.$IWB_DOMAIN"
  "n8n.$IWB_DOMAIN"
  "${COMPOSE_PROJECT_NAME}media.${IWB_DOMAIN}"
)

log "Attempting to restore certs from cloud"

if ! /var/setup/scripts/backup/iwb-restore.sh ssl; then
  log "$ERR_PREFIX Cloud cert restore failed — Will attempt new cert creation."
else
  CERTS_RESTORED=true
  DHPARAM_RESTORED=true
fi

# === Request certificates if needed ===
if [ "$CERTS_RESTORED" != true ]; then
  echo -e "$IWB_PREFIX Starting temporary Nginx for HTTP-01 challenge..."

  echo -e "${IWB_PREFIX} Configuring Nginx site templates..."
  mkdir -p "$IWB_NGINX_CONF_DIR"

  for SUBDOMAIN in "${IWB_SSL_DOMAINS[@]}"; do
    # Trim to base name for template
    SITE=$(echo "$SUBDOMAIN" | sed "s/\.$IWB_DOMAIN$//")
    [ "$SITE" = "$IWB_DOMAIN" ] && SITE="default"

    TEMPLATE_FILE="$IWB_SSL_TEMPLATE_DIR/${SITE}.conf.template"
    OUTPUT_FILE="$IWB_SSL_TEMPLATE_DIR/${SITE}.conf"
    TARGET_LINK="$IWB_NGINX_CONF_DIR/${SITE}.conf"

    if [ -f "$TEMPLATE_FILE" ]; then
      sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"
      ln -sf "$OUTPUT_FILE" "$TARGET_LINK"
      log "Linked $SITE.conf for $SUBDOMAIN"
    else
      ## I commented this out to not report errors... as it's working
      ## regardless
      #echo -e "${IWB_PREFIX} $ERR_PREFIX Missing template: $TEMPLATE_FILE"
      # Template not found, skipping without error
      :
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

  # Build certbot domain args
  DOMAIN_ARGS=()
  for d in "${IWB_SSL_DOMAINS[@]}"; do
    DOMAIN_ARGS+=("-d" "$d")
  done

  if certbot certonly --nginx -n --agree-tos \
      --email "$IWB_MAIL_USER@$IWB_DOMAIN" \
      "${DOMAIN_ARGS[@]}"; then
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
