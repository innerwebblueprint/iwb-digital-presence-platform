#!/bin/bash
# setup-n8n.sh – IWB Digital Presence Platform – n8n setup script

set -euo pipefail
MODULE="N8N"

log "${MODULE} Starting n8n setup..."

# === Ensure data directory for n8n exists and is symlinked ===
if [ ! -d "/var/www/html/n8n" ]; then
  log "${MODULE} Creating /var/www/html/n8n directory for persistent storage..."
  mkdir -p /var/www/html/n8n
fi

# Ensure proper ownership of the data directory
chown -R n8n:n8n /var/www/html/n8n

# Create symlink for the n8n user (not root) since supervisord runs as n8n user
if [ ! -L "/home/n8n/.n8n" ]; then
  log "${MODULE} Creating n8n user home directory..."
  mkdir -p /home/n8n
  chown n8n:n8n /home/n8n
  
  log "${MODULE} Linking /home/n8n/.n8n to /var/www/html/n8n..."
  rm -rf /home/n8n/.n8n 2>/dev/null || true
  ln -sf /var/www/html/n8n /home/n8n/.n8n
  chown -h n8n:n8n /home/n8n/.n8n
else
  log "${MODULE} /home/n8n/.n8n is already linked to /var/www/html/n8n"
fi

# === Attempt restore from backup via iwb-restore.sh ===
log "${MODULE} Attempting to restore from cloud backup..."

if /var/setup/scripts/backup/iwb-restore.sh n8n; then
  log "Restore successful."
else
  log "$ERR_PREFIX Restore failed or backup not found. Proceeding without restore."
fi

# === Set shared base environment ===
export N8N_HOST="localhost"
export N8N_PORT=5678
export N8N_PROTOCOL="http"
export N8N_EDITOR_BASE_URL="https://n8n.${IWB_DOMAIN}"
export WEBHOOK_URL="https://n8n.${IWB_DOMAIN}"
export N8N_RUNNERS_ENABLED=true
export N8N_RUNNERS_WORKER_COUNT=4

# === Disable all telemetry and external connections ===
export N8N_DIAGNOSTICS_ENABLED=false
export N8N_VERSION_NOTIFICATIONS_ENABLED=false
export N8N_TEMPLATES_ENABLED=false
export EXTERNAL_FRONTEND_HOOKS_URLS=""
export N8N_DIAGNOSTICS_CONFIG_FRONTEND=""
export N8N_DIAGNOSTICS_CONFIG_BACKEND=""

export N8N_JWT_SECRET="${IWB_N8N_JWT_SECRET:-$(openssl rand -hex 32)}"
log "${MODULE} Full User Management enabled. First user must be created manually in UI."

# # === Toggle user mode ===
# if [[ "${IWB_N8N_USER_MANAGEMENT}" == "true" ]]; then
#   export N8N_USER_MANAGEMENT_DISABLED=false
#   export N8N_JWT_SECRET="${IWB_N8N_JWT_SECRET:-$(openssl rand -hex 32)}"
#   log "${MODULE} Full User Management enabled. First user must be created manually in UI."
# else
#   export N8N_BASIC_AUTH_ACTIVE=true
#   export N8N_BASIC_AUTH_USER="${IWB_N8N_USER}"
#   export N8N_BASIC_AUTH_PASSWORD="${IWB_N8N_PASSWORD}"
#   export N8N_USER_MANAGEMENT_DISABLED=true
#   log "${MODULE} Basic Auth enabled for user '$N8N_BASIC_AUTH_USER'."
# fi



log "${MODULE} n8n environment ready."
