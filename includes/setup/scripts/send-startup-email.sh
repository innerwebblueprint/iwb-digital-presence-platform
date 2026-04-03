#!/bin/bash
# includes/setup/scripts/send-startup-email.sh
# Sends a notification email on every container startup/restart
set -e

source /var/setup/scripts/setup-env.sh

MODULE="STARTUP EMAIL"
LOG_FILE="/var/log/iwb-email.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting background startup notification email..."

sleep 10
log "Preparing to send container startup notification email..."

# Get WordPress admin/editor users if WordPress is installed
WP_USERS_SECTION=""
WP_ROOT="/var/www/html/wordpress"
if wp core is-installed --path="$WP_ROOT" --allow-root 2>/dev/null; then
  log "WordPress is installed, fetching admin and editor users..."
  WP_LOOKUP_ERROR=0

  # Primary lookup: role-filtered queries
  if WP_ADMINS_RAW=$(wp user list --role=administrator --fields=user_login,user_email,roles --format=csv --path="$WP_ROOT" --allow-root 2>&1); then
    WP_ADMINS=$(echo "$WP_ADMINS_RAW" | tail -n +2)
  else
    WP_ADMINS=""
    WP_LOOKUP_ERROR=1
    log "$ERR_PREFIX Failed to query WordPress administrator users: $WP_ADMINS_RAW"
  fi

  if WP_EDITORS_RAW=$(wp user list --role=editor --fields=user_login,user_email,roles --format=csv --path="$WP_ROOT" --allow-root 2>&1); then
    WP_EDITORS=$(echo "$WP_EDITORS_RAW" | tail -n +2)
  else
    WP_EDITORS=""
    WP_LOOKUP_ERROR=1
    log "$ERR_PREFIX Failed to query WordPress editor users: $WP_EDITORS_RAW"
  fi

  WP_USERS=$(printf "%s\n%s\n" "$WP_ADMINS" "$WP_EDITORS" | grep -v '^$' | sort -u || true)

  # Fallback lookup: fetch all users and filter by role text
  if [ -z "$WP_USERS" ]; then
    log "Role-filtered lookup returned no users; trying fallback all-users query..."
    if WP_ALL_USERS_RAW=$(wp user list --fields=user_login,user_email,roles --format=csv --path="$WP_ROOT" --allow-root 2>&1); then
      WP_USERS=$(echo "$WP_ALL_USERS_RAW" | tail -n +2 | grep -Ei 'administrator|editor' || true)
    else
      WP_LOOKUP_ERROR=1
      log "$ERR_PREFIX Failed fallback WordPress user query: $WP_ALL_USERS_RAW"
    fi
  fi
  
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
  elif [ "$WP_LOOKUP_ERROR" -eq 1 ]; then
    WP_USERS_SECTION=$(cat <<EOF


╔════════════════════════════════════════════════════════════╗
║            WordPress Admin & Editor Users                  ║
╚════════════════════════════════════════════════════════════╝

WordPress user lookup failed during startup (likely temporary service readiness timing).
Try again after startup settles: wp user list --path=$WP_ROOT --allow-root

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
MAIL_FROM_NAME="IWB Digital Presence Platform"
MAIL_FROM_HEADER="${MAIL_FROM_NAME} <${MAIL_FROM}>"
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

# Wait for postfix to become ready
SMTP_WAIT_SECONDS=0
until nc -z 127.0.0.1 25; do
  SMTP_WAIT_SECONDS=$((SMTP_WAIT_SECONDS + 2))
  if [ "$SMTP_WAIT_SECONDS" -ge 120 ]; then
    log "$ERR_PREFIX Postfix not ready after ${SMTP_WAIT_SECONDS}s; skipping startup email send"
    (return 0 2>/dev/null) || exit 0
  fi
  log "Waiting for postfix (port 25) before sending startup email..."
  sleep 2
done

# Send email
if {
  echo "To: $MAIL_TO"
  echo "From: $MAIL_FROM_HEADER"
  echo "Subject: $SUBJECT"
  echo "Date: $(LC_ALL=C date -R)"
  echo "Message-Id: <startup.$(date +%s).$$@mail.${IWB_DOMAIN}>"
  echo "MIME-Version: 1.0"
  echo "Auto-Submitted: auto-generated"
  echo "Content-Type: text/plain; charset=UTF-8"
  echo ""
  echo "$BODY"
} | /usr/sbin/sendmail -t -f "$MAIL_FROM"; then
  log "Startup notification email queued successfully to $MAIL_TO"
else
  log "$ERR_PREFIX Failed to queue startup notification email"
fi

(return 0 2>/dev/null) || exit 0
