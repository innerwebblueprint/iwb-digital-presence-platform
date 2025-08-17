#!/bin/bash
# includes/setup/scripts/setup-cron.sh

CALL_MODULE=$MODULE
MODULE="SETUP CRON"

# Load environment and logging
source /var/setup/scripts/setup-env.sh

log "Setting up cron jobs for backup..."

# Make sure cron daemon exists
if ! command -v crond &> /dev/null; then
  log "$ERR_PREFIX crond binary not found! Exiting."
  exit 1
fi

# Create crontab file if it doesn't exist
CRON_FILE="/etc/crontabs/root"

# Ensure correct SHELL and PATH at top of crontab
grep -q "SHELL=" "$CRON_FILE" || echo "SHELL=/bin/bash" >> "$CRON_FILE"
grep -q "PATH=" "$CRON_FILE" || echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> "$CRON_FILE"

# Trigger WordPress cron manually every 5 minutes
grep -q "wp-cron.php" "$CRON_FILE" || echo "*/5 * * * * curl -fsSL -k -H \"Host: ${IWB_DOMAIN}\" https://127.0.0.1/wp-cron.php > /dev/null 2>&1" >> "$CRON_FILE"

# Add backup jobs if not already present
## PostfixAdmin
grep -q "iwb-backup.sh postfix hourly" "$CRON_FILE" || echo "10 * * * * . /var/data/state/docker-env.sh && iwb-backup.sh postfix hourly > /dev/null 2>&1" >> "$CRON_FILE"
## Mail
grep -q "iwb-backup.sh mail hourly" "$CRON_FILE" || echo "5 * * * * . /var/data/state/docker-env.sh && iwb-backup.sh mail hourly > /dev/null 2>&1" >> "$CRON_FILE"
## Wordpress
grep -q "iwb-backup.sh wpdb hourly" "$CRON_FILE" || echo "15 * * * * . /var/data/state/docker-env.sh && iwb-backup.sh wpdb hourly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh wphtml daily" "$CRON_FILE" || echo "0 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh wphtml daily > /dev/null 2>&1" >> "$CRON_FILE"
## n8n
grep -q "iwb-backup.sh n8n hourly" "$CRON_FILE" || echo "1 * * * * . /var/data/state/docker-env.sh && iwb-backup.sh n8n hourly > /dev/null 2>&1" >> "$CRON_FILE"

#grep -q "iwb-logtest.sh" "$CRON_FILE" || echo "* * * * * . /var/data/state/docker-env.sh && iwb-logtest.sh 2>&1" >> "$CRON_FILE"

## certbot renew
grep -q "/usr/bin/certbot renew --quiet --deploy-hook" "$CRON_FILE" || \
echo "0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook \"/var/setup/scripts/cert-renew-hook.sh\" > /dev/null 2>&1" >> "$CRON_FILE"


log "Cron jobs configured."

MODULE=$CALL_MODULE
(return 0 2>/dev/null) || exit 0

