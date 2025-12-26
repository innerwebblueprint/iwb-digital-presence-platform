#!/bin/bash
# includes/setup/scripts/send-startup-email.sh
# Sends a notification email on every container startup/restart
set -e

log "Starting background startup notification email..."

source /var/setup/scripts/setup-env.sh

MODULE="STARTUP EMAIL"
LOG_FILE="/var/log/iwb-email.log"
exec > >(tee -a "$LOG_FILE") 2>&1

sleep 10
log "Preparing to send container startup notification email..."

# Get WordPress admin/editor users if WordPress is installed
WP_USERS_SECTION=""
WP_ROOT="/var/www/html/wordpress"
if wp core is-installed --path="$WP_ROOT" --allow-root 2>/dev/null; then
  log "WordPress is installed, fetching admin and editor users..."
  
  # Get users with administrator or editor roles (fetch separately and combine)
  WP_ADMINS=$(wp user list --role=administrator --fields=user_login,user_email,roles --format=csv --path="$WP_ROOT" --allow-root 2>/dev/null | tail -n +2)
  WP_EDITORS=$(wp user list --role=editor --fields=user_login,user_email,roles --format=csv --path="$WP_ROOT" --allow-root 2>/dev/null | tail -n +2)
  WP_USERS=$(printf "%s\n%s" "$WP_ADMINS" "$WP_EDITORS" | grep -v '^$')
  
  if [ -n "$WP_USERS" ]; then
    # Format the users list for email
    USER_LIST=""
    while IFS=',' read -r user_login user_email roles; do
      # Clean up quotes from CSV
      user_login=$(echo "$user_login" | tr -d '"')
      user_email=$(echo "$user_email" | tr -d '"')
      roles=$(echo "$roles" | tr -d '"')
      
      USER_LIST="${USER_LIST}${user_login}\t${user_email}\t${roles}\n"
    done <<< "$WP_USERS"
    
    WP_USERS_SECTION=$(cat <<EOF


╔════════════════════════════════════════════════════════════╗
║            WordPress Admin & Editor Users                  ║
╚════════════════════════════════════════════════════════════╝

$(printf "%-20s %-30s %s\n" "Username" "Email" "Role")
$(printf "%-20s %-30s %s\n" "--------------------" "------------------------------" "---------------")
$(echo -e "$USER_LIST" | while IFS=$'\t' read -r login email role; do
  printf "%-20s %-30s %s\n" "$login" "$email" "$role"
done)

EOF
)
  else
    WP_USERS_SECTION=$(cat <<EOF


╔════════════════════════════════════════════════════════════╗
║            WordPress Admin & Editor Users                  ║
╚════════════════════════════════════════════════════════════╝

No admin or editor users found (this shouldn't happen - check WordPress installation)

EOF
)
  fi
else
  log "WordPress not yet installed or not accessible - skipping user list"
  WP_USERS_SECTION=$(cat <<EOF


╔════════════════════════════════════════════════════════════╗
║            WordPress Admin & Editor Users                  ║
╚════════════════════════════════════════════════════════════╝

WordPress still initializing - users list not available at this time.
Check your next startup email or log into WordPress admin to view users.

EOF
)
fi

# Compose email
MAIL_FROM="${IWB_MAIL_USER}@$IWB_DOMAIN"
MAIL_TO="$MAIL_FROM"
SUBJECT="Container Started - ${IWB_DOMAIN}"
STARTUP_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")

BODY=$(cat <<EOF
Hello!

Your IWB Digital Presence Platform container has started.

╔════════════════════════════════════════════════════════════╗
║                    Container Information                   ║
╚════════════════════════════════════════════════════════════╝

Domain: ${IWB_DOMAIN}
Startup Time: ${STARTUP_TIME}
Container: ${HOSTNAME}


╔════════════════════════════════════════════════════════════╗
║                    Service Access URLs                     ║
╚════════════════════════════════════════════════════════════╝

Main Website:    https://${IWB_DOMAIN}
WordPress Admin: https://${IWB_DOMAIN}/wp-admin
Rspamd Web UI:   https://rspamd.${IWB_DOMAIN}
n8n Automation:  https://n8n.${IWB_DOMAIN}

${WP_USERS_SECTION}

╔════════════════════════════════════════════════════════════╗
║              Rspamd Anti-Spam Web Interface                ║
╚════════════════════════════════════════════════════════════╝

Rspamd URL: https://rspamd.${IWB_DOMAIN}

Normal Password: ${IWB_RSPAMD_CONTROLLER_PASSWORD}
Enable Password: ${IWB_RSPAMD_CONTROLLER_ENABLE_PASSWORD}

(The enable password allows you to enable/disable Rspamd features)


╔════════════════════════════════════════════════════════════╗
║                    Important Notes                         ║
╚════════════════════════════════════════════════════════════╝

• WordPress credentials are managed through WordPress itself
  (use password reset if needed: https://${IWB_DOMAIN}/wp-login.php?action=lostpassword)

• n8n credentials are set during first-time web UI setup

• To view all auto-generated passwords, run inside the container:
  /var/setup/scripts/show-passwords.sh

• For assistance, visit: https://www.innerwebblueprint.com/support


--
IWB Digital Presence Platform
Container Startup Notification System
EOF
)

# Send email
{
  echo "To: $MAIL_TO"
  echo "From: $MAIL_FROM"
  echo "Subject: $SUBJECT"
  echo "Content-Type: text/plain; charset=UTF-8"
  echo ""
  echo "$BODY"
} | /usr/sbin/sendmail -t

if [ $? -eq 0 ]; then
  log "Startup notification email queued successfully to $MAIL_TO"
else
  log "$ERR_PREFIX Failed to queue startup notification email"
fi
