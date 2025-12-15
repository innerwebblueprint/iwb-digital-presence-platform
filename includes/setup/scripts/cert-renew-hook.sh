#!/bin/bash
# includes/setup/scripts/cert-renew-hook.sh

set -euo pipefail

LOG_FILE="${IWB_CERT_RENEW_HOOK_LOG_FILE:-/var/log/letsencrypt/iwb-cert-renew-hook.log}"
mkdir -p "$(dirname "$LOG_FILE")" || true
touch "$LOG_FILE" || true
chmod 600 "$LOG_FILE" 2>/dev/null || true

log() {
  local msg="$1"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "[IWB][CERT-RENEW-HOOK] $ts $msg" | tee -a "$LOG_FILE" >/dev/null
}

err() {
  log "ERROR $1"
}

# Certbot deploy-hook provides these when a lineage is renewed.
RENEWED_LINEAGE="${RENEWED_LINEAGE:-}"
RENEWED_DOMAINS="${RENEWED_DOMAINS:-}"

log "Deploy-hook invoked. renewed_lineage='${RENEWED_LINEAGE}' renewed_domains='${RENEWED_DOMAINS}'"

CERT_FULLCHAIN=""
if [ -n "$RENEWED_LINEAGE" ] && [ -f "$RENEWED_LINEAGE/fullchain.pem" ]; then
  CERT_FULLCHAIN="$RENEWED_LINEAGE/fullchain.pem"
fi

if [ -n "$CERT_FULLCHAIN" ]; then
  CERT_DATES="$(openssl x509 -noout -dates -in "$CERT_FULLCHAIN" 2>/dev/null || true)"
  CERT_FP="$(openssl x509 -noout -fingerprint -sha256 -in "$CERT_FULLCHAIN" 2>/dev/null || true)"
  log "Renewed cert on disk: $CERT_DATES"
  [ -n "$CERT_FP" ] && log "Renewed cert fingerprint: $CERT_FP"
else
  err "Could not locate renewed fullchain.pem (renewed_lineage='$RENEWED_LINEAGE')."
fi

log "Reloading/restarting services to pick up renewed cert..."

restart_via_supervisor() {
  local svc="$1"
  if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl restart "$svc" >/dev/null 2>&1 && return 0
  fi
  return 1
}

reload_fallback() {
  local svc="$1"
  case "$svc" in
    nginx)
      command -v nginx >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1 && return 0
      ;;
    postfix)
      command -v postfix >/dev/null 2>&1 && postfix reload >/dev/null 2>&1 && return 0
      ;;
    dovecot)
      command -v dovecot >/dev/null 2>&1 && dovecot reload >/dev/null 2>&1 && return 0
      ;;
  esac
  return 1
}

for svc in nginx postfix dovecot; do
  if restart_via_supervisor "$svc"; then
    log "Service restarted via supervisorctl: $svc"
  elif reload_fallback "$svc"; then
    log "Service reloaded via fallback command: $svc"
  else
    err "Failed to reload/restart service: $svc"
  fi
done

if command -v openssl >/dev/null 2>&1; then
  # Confirm what Dovecot is actually serving after reload.
  if echo | openssl s_client -connect 127.0.0.1:993 2>/dev/null | openssl x509 -noout -dates -fingerprint -sha256 >/tmp/iwb-imap-cert.txt 2>/dev/null; then
    log "IMAP(993) served cert: $(tr '\n' ';' </tmp/iwb-imap-cert.txt | sed 's/;*$//')"
  else
    err "Unable to probe IMAP(993) with openssl s_client"
  fi
fi

log "Attempting to back up renewed certificates to cloud storage (best-effort)..."
if [ -x /var/setup/scripts/backup/iwb-backup.sh ]; then
  if /var/setup/scripts/backup/iwb-backup.sh ssl snapshot >/dev/null 2>&1; then
    log "SSL certificate backup completed successfully"
  else
    err "SSL certificate backup failed"
  fi
else
  err "Backup script missing: /var/setup/scripts/backup/iwb-backup.sh"
fi

# Optional notification email (only if container env provides these vars)
if [ -n "${IWB_MAIL_USER:-}" ] && [ -n "${IWB_DOMAIN:-}" ] && command -v sendmail >/dev/null 2>&1; then
  RENEWAL_DATE="$(date +"%Y-%m-%d %H:%M:%S %Z")"
  CERT_EXPIRY=""
  if [ -n "$CERT_FULLCHAIN" ]; then
    CERT_EXPIRY="$(openssl x509 -enddate -noout -in "$CERT_FULLCHAIN" 2>/dev/null | cut -d= -f2)"
  fi

  cat <<EOF | sendmail -t
To: ${IWB_MAIL_USER}@${IWB_DOMAIN}
From: admin@${IWB_DOMAIN}
Subject: SSL Certificate Renewed - ${IWB_DOMAIN}

SSL Certificate Renewal Notification
=====================================

Domains: ${RENEWED_DOMAINS:-unknown}
Renewal Date: ${RENEWAL_DATE}
Certificate Expires: ${CERT_EXPIRY:-unknown}

Services reloaded to pick up renewed certificates:
- Nginx
- Postfix
- Dovecot

--
IWB Digital Presence Platform
Automated Certificate Management
EOF

  log "Renewal notification email sent to ${IWB_MAIL_USER}@${IWB_DOMAIN}"
else
  log "Skipping notification email (IWB_MAIL_USER/IWB_DOMAIN/sendmail not available in hook environment)"
fi

log "Deploy-hook finished."
