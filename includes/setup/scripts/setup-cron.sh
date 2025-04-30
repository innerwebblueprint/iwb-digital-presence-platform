#!/bin/bash
# includes/setup/scripts/setup-cron.sh

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

# Add backup jobs if not already present
grep -q "iwb-backup.sh mail hourly" "$CRON_FILE" || echo "5 * * * * . /var/data/state/docker-env.sh && iwb-backup.sh mail hourly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh postfix hourly" "$CRON_FILE" || echo "10 * * * * . /var/data/state/docker-env.sh && iwb-backup.sh postfix hourly > /dev/null 2>&1" >> "$CRON_FILE"

#grep -q "iwb-logtest.sh" "$CRON_FILE" || echo "* * * * * . /var/data/state/docker-env.sh && iwb-logtest.sh 2>&1" >> "$CRON_FILE"

# # Ensure correct SHELL and PATH at top of crontab
# grep -q "SHELL=" "$CRON_FILE" || echo "SHELL=/bin/bash" >> "$CRON_FILE"
# grep -q "PATH=" "$CRON_FILE" || echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> "$CRON_FILE"

# # Add backup jobs if not already present
# grep -q "iwb-backup.sh mail hourly" "$CRON_FILE" || echo "5 * * * * . /var/data/state/docker-env.sh && iwb-backup.sh mail hourly >> /var/log/iwb-backup.log 2>&1" >> "$CRON_FILE"
# grep -q "iwb-backup.sh postfix hourly" "$CRON_FILE" || echo "10 * * * * . /var/data/state/docker-env.sh && iwb-backup.sh postfix hourly >> /var/log/iwb-backup.log 2>&1" >> "$CRON_FILE"


log "Cron jobs configured."




(return 0 2>/dev/null) || exit 0

