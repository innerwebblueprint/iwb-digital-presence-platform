#!/bin/bash
# includes/setup/scripts/send-wp-admin-email.sh
set -e

log "Starting background wp admin email sending..."

source /var/setup/scripts/setup-env.sh

MODULE="WP ADMIN EMAIL"
LOG_FILE="/var/log/iwb-email.log"
exec > >(tee -a "$LOG_FILE") 2>&1

sleep 10
log "Starting background wp admin email sending..."
log "Queuing admin password email to $WEBMAIL_USER..."

  # Optionally delete password file
  # rm -f "$TEMP_PASS_FILE"


export IWB_WP_ADMIN_PASSWORD="$(< /tmp/wp-admin-pass.txt)"


log "$IWB_WP_ADMIN_USER : $IWB_WP_ADMIN_PASSWORD"

# Send credentials
log "Qued Sending admin password to $WEBMAIL_USER..."

# Compose email with new user and password:
MAIL_FROM="${IWB_MAIL_USER}@$IWB_DOMAIN"
MAIL_TO="$MAIL_FROM"
SUBJECT="Your WordPress admin credentials for www.${IWB_DOMAIN}"

BODY=$(cat <<EOF
Hello!

Your WordPress admin user account is: $IWB_WP_ADMIN_USER\n\n
Your password for that account is: $IWB_WP_ADMIN_PASSWORD\n\n

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
  log "$ERR_PREFIX Failed to send WordPress admin email notification to $MAIL_TO"
  return 1
else
  log "email sent to $IWB_MAIL_USER@$IWB_DOMAIN please check for WordPress admin credentials"
fi

(return 0 2>/dev/null) || exit 0