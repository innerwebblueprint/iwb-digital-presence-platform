#!/bin/bash
# includes/setup/scripts/send-wp-admin-email.sh
set -e

log "Starting background credentials email sending..."

source /var/setup/scripts/setup-env.sh

MODULE="CREDENTIALS EMAIL"
LOG_FILE="/var/log/iwb-email.log"
exec > >(tee -a "$LOG_FILE") 2>&1

sleep 10
log "Preparing to send platform credentials email..."
log "Email will include WordPress admin and Rspamd web UI credentials..."

  # Optionally delete password file
  # rm -f "$TEMP_PASS_FILE"


export IWB_WP_ADMIN_PASSWORD="$(< /tmp/wp-admin-pass.txt)"


log "WordPress Admin: $IWB_WP_ADMIN_USER"
log "Rspamd passwords loaded from state files"

# Send credentials
log "Queuing credentials email to $MAIL_FROM..."

# Compose email with new user and password:
MAIL_FROM="${IWB_MAIL_USER}@$IWB_DOMAIN"
MAIL_TO="$MAIL_FROM"
SUBJECT="Your IWB Digital Presence Platform credentials for ${IWB_DOMAIN}"

BODY=$(cat <<EOF
Hello!

Your IWB Digital Presence Platform is now running at: https://${IWB_DOMAIN}

╔════════════════════════════════════════════════════════════╗
║                 WordPress Admin Credentials                ║
╚════════════════════════════════════════════════════════════╝

WordPress Admin URL: https://${IWB_DOMAIN}/wp-admin
Admin Username: ${IWB_WP_ADMIN_USER}
Admin Password: ${IWB_WP_ADMIN_PASSWORD}


╔════════════════════════════════════════════════════════════╗
║              Rspamd Anti-Spam Web Interface                ║
╚════════════════════════════════════════════════════════════╝

Rspamd Web UI: https://${IWB_DOMAIN}/rspamd
Normal Access Password: ${IWB_RSPAMD_CONTROLLER_PASSWORD}
Enable/Disable Password: ${IWB_RSPAMD_CONTROLLER_ENABLE_PASSWORD}


╔════════════════════════════════════════════════════════════╗
║            n8n Automation Platform - IMPORTANT!            ║
╚════════════════════════════════════════════════════════════╝

⚠️  FIRST-TIME SETUP REQUIRED ⚠️

n8n URL: https://${IWB_DOMAIN}/n8n

ACTION REQUIRED: You must set your n8n admin username and password
on first login. This is REQUIRED for security.

1. Visit: https://${IWB_DOMAIN}/n8n
2. Create your admin account when prompted
3. Store these credentials securely

Note: The n8n credentials in your .env file are NOT used - you must
set them through the web interface on first login.


╔════════════════════════════════════════════════════════════╗
║                   Important Notes                          ║
╚════════════════════════════════════════════════════════════╝

• Store all credentials securely
• All database passwords are auto-generated and stored in the container
• To view all passwords, run inside the container:
  /var/setup/scripts/show-passwords.sh

• Need help? Visit: https://innerwebblueprint.com/support


– Your IWB Server 🌐
EOF
)

# === Wait for postfix to become ready ===
while ! nc -z 127.0.0.1 25; do
    log "Waiting for postfix (port 25)..."
    sleep 4
done

# --- Send email ---
set -o pipefail

# --- Send email ---
echo -e "$BODY" | mail -s "$SUBJECT" -r "$MAIL_FROM" "$MAIL_TO"

if [ $? -ne 0 ]; then
  log "$ERR_PREFIX Failed to send platform credentials email notification to $MAIL_TO"
  return 1
else
  log "Credentials email sent to $IWB_MAIL_USER@$IWB_DOMAIN - includes WordPress admin & Rspamd web UI passwords"
fi

(return 0 2>/dev/null) || exit 0