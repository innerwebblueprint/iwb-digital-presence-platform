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

should_use_self_signed=false
if [ "${IWB_LOCAL_DEV}" = "true" ] || [ "${IWB_SSL_SELF_SIGNED_FALLBACK}" = "true" ]; then
  should_use_self_signed=true
fi

generate_self_signed_certs() {
  local cert_root="/etc/letsencrypt"
  local live_dir="${cert_root}/live/${IWB_DOMAIN}"
  local archive_dir="${cert_root}/archive/${IWB_DOMAIN}"
  local key_file="${live_dir}/privkey.pem"
  local cert_file="${live_dir}/fullchain.pem"
  local chain_file="${live_dir}/chain.pem"
  local options_file="${cert_root}/options-ssl-nginx.conf"
  local dhparam_file="${cert_root}/ssl-dhparams.pem"
  local san_list
  local regenerate_dhparam=false

  san_list="DNS:${IWB_DOMAIN}"
  for d in "${IWB_SSL_DOMAINS[@]}"; do
    if [ "$d" != "$IWB_DOMAIN" ]; then
      san_list="${san_list},DNS:${d}"
    fi
  done

  mkdir -p "${live_dir}" "${archive_dir}" "${cert_root}/renewal"

  log "Generating self-signed certificate for local development..."
  if ! openssl req -x509 -nodes -newkey rsa:2048 \
      -days 365 \
      -subj "/CN=${IWB_DOMAIN}" \
      -addext "subjectAltName=${san_list}" \
      -keyout "${key_file}" \
      -out "${cert_file}" >/dev/null 2>&1; then
    log "$ERR_PREFIX Failed generating self-signed certificate."
    return 1
  fi

  cp -f "${cert_file}" "${chain_file}"
  cp -f "${cert_file}" "${archive_dir}/fullchain1.pem"
  cp -f "${chain_file}" "${archive_dir}/chain1.pem"
  cp -f "${key_file}" "${archive_dir}/privkey1.pem"

  cat > "${options_file}" <<'EOF'
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_stapling off;
ssl_stapling_verify off;
EOF

  if [ -f "${dhparam_file}" ]; then
    if ! openssl dhparam -in "${dhparam_file}" -text -noout 2>/dev/null | grep -q "(2048 bit)\|(3072 bit)\|(4096 bit)"; then
      log "Existing dhparam is too small for modern TLS security defaults. Regenerating..."
      regenerate_dhparam=true
    fi
  else
    regenerate_dhparam=true
  fi

  if [ "${regenerate_dhparam}" = true ]; then
    log "Generating dhparam (2048-bit) for self-signed TLS setup..."
    if ! openssl dhparam -out "${dhparam_file}" 2048 >/dev/null 2>&1; then
      log "$ERR_PREFIX Failed generating dhparam file for self-signed TLS setup."
      return 1
    fi
  fi

  cat > "${cert_root}/renewal/${IWB_DOMAIN}.conf" <<EOF
version = 2.0.0
archive_dir = ${archive_dir}
cert = ${cert_file}
privkey = ${key_file}
chain = ${chain_file}
fullchain = ${cert_file}

[renewalparams]
authenticator = nginx
server = https://acme-v02.api.letsencrypt.org/directory
EOF

  CERTS_RESTORED=true
  DHPARAM_RESTORED=true
  log "Self-signed certificates generated for local development mode."
  return 0
}

# === Request certificates if needed ===
if [ "$CERTS_RESTORED" != true ]; then
  if [ "$should_use_self_signed" = true ]; then
    if ! generate_self_signed_certs; then
      return 1
    fi
  else
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
