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

# --- Per-instance randomized staggering ---
# We compute deterministic offsets based on IWB_DOMAIN to avoid synchronized runs
# across multiple instances on the same host. Uses cksum modulo arithmetic.
compute_offset() {
  local seed="$1"       # typically dataset+interval
  local base_min="$2"  # base minute window start
  local span="$3"      # size of window (minutes)
  local checksum
  checksum=$(echo "${IWB_DOMAIN}-${seed}" | cksum | awk '{print $1}')
  echo $(( base_min + (checksum % span) ))
}

# Trigger WordPress cron manually every 5 minutes
grep -q "wp-cron.php" "$CRON_FILE" || echo "*/5 * * * * curl -fsSL -k -H \"Host: ${IWB_DOMAIN}\" https://127.0.0.1/wp-cron.php > /dev/null 2>&1" >> "$CRON_FILE"

# Add backup jobs if not already present
## PostfixAdmin
POSTFIX_HOURLY_MIN=$(compute_offset "postfix-hourly" 3 10)
grep -q "iwb-backup.sh postfix hourly" "$CRON_FILE" || echo "$POSTFIX_HOURLY_MIN * * * * . /var/data/state/docker-env.sh && iwb-backup.sh postfix hourly > /dev/null 2>&1" >> "$CRON_FILE"
## Mail
MAIL_HOURLY_MIN=$(compute_offset "mail-hourly" 0 10)
grep -q "iwb-backup.sh mail hourly" "$CRON_FILE" || echo "$MAIL_HOURLY_MIN * * * * . /var/data/state/docker-env.sh && iwb-backup.sh mail hourly > /dev/null 2>&1" >> "$CRON_FILE"
## Wordpress
WPDB_HOURLY_MIN=$(compute_offset "wpdb-hourly" 10 10)
grep -q "iwb-backup.sh wpdb hourly" "$CRON_FILE" || echo "$WPDB_HOURLY_MIN * * * * . /var/data/state/docker-env.sh && iwb-backup.sh wpdb hourly > /dev/null 2>&1" >> "$CRON_FILE"
WPHTML_DAILY_MIN=$(compute_offset "wphtml-daily" 0 10)
grep -q "iwb-backup.sh wphtml daily" "$CRON_FILE" || echo "$WPHTML_DAILY_MIN 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh wphtml daily > /dev/null 2>&1" >> "$CRON_FILE"
## n8n
N8N_HOURLY_MIN=$(compute_offset "n8n-hourly" 20 10)
grep -q "iwb-backup.sh n8n hourly" "$CRON_FILE" || echo "$N8N_HOURLY_MIN * * * * . /var/data/state/docker-env.sh && iwb-backup.sh n8n hourly > /dev/null 2>&1" >> "$CRON_FILE"

# --- Additional scheduled backups: daily, weekly, monthly, yearly ---
# Daily backups in window 02:00–02:59 with deterministic minutes
MAIL_DAILY_MIN=$(compute_offset "mail-daily" 0 60)
POSTFIX_DAILY_MIN=$(compute_offset "postfix-daily" 0 60)
WPDB_DAILY_MIN=$(compute_offset "wpdb-daily" 0 60)
N8N_DAILY_MIN=$(compute_offset "n8n-daily" 0 60)
RSPAMD_DAILY_MIN=$(compute_offset "rspamd-daily" 0 60)
DKIM_DAILY_MIN=$(compute_offset "dkim-daily" 0 60)
SSL_DAILY_MIN=$(compute_offset "ssl-daily" 0 60)
grep -q "iwb-backup.sh mail daily" "$CRON_FILE" || echo "$MAIL_DAILY_MIN 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh mail daily > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh postfix daily" "$CRON_FILE" || echo "$POSTFIX_DAILY_MIN 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh postfix daily > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh wpdb daily" "$CRON_FILE" || echo "$WPDB_DAILY_MIN 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh wpdb daily > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh n8n daily" "$CRON_FILE" || echo "$N8N_DAILY_MIN 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh n8n daily > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh rspamd daily" "$CRON_FILE" || echo "$RSPAMD_DAILY_MIN 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh rspamd daily > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh dkim daily" "$CRON_FILE" || echo "$DKIM_DAILY_MIN 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh dkim daily > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh ssl daily" "$CRON_FILE" || echo "$SSL_DAILY_MIN 2 * * * . /var/data/state/docker-env.sh && iwb-backup.sh ssl daily > /dev/null 2>&1" >> "$CRON_FILE"

# Weekly backups (Sunday in window 02:00–03:59)
MAIL_WEEKLY_MIN=$(compute_offset "mail-weekly" 0 60)
POSTFIX_WEEKLY_MIN=$(compute_offset "postfix-weekly" 0 60)
WPDB_WEEKLY_MIN=$(compute_offset "wpdb-weekly" 0 60)
WPHTML_WEEKLY_MIN=$(compute_offset "wphtml-weekly" 0 60)
N8N_WEEKLY_MIN=$(compute_offset "n8n-weekly" 0 60)
RSPAMD_WEEKLY_MIN=$(compute_offset "rspamd-weekly" 0 60)
DKIM_WEEKLY_MIN=$(compute_offset "dkim-weekly" 0 60)
SSL_WEEKLY_MIN=$(compute_offset "ssl-weekly" 0 60)
grep -q "iwb-backup.sh mail weekly" "$CRON_FILE" || echo "$MAIL_WEEKLY_MIN 2 * * 0 . /var/data/state/docker-env.sh && iwb-backup.sh mail weekly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh postfix weekly" "$CRON_FILE" || echo "$POSTFIX_WEEKLY_MIN 2 * * 0 . /var/data/state/docker-env.sh && iwb-backup.sh postfix weekly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh wpdb weekly" "$CRON_FILE" || echo "$WPDB_WEEKLY_MIN 2 * * 0 . /var/data/state/docker-env.sh && iwb-backup.sh wpdb weekly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh wphtml weekly" "$CRON_FILE" || echo "$WPHTML_WEEKLY_MIN 2 * * 0 . /var/data/state/docker-env.sh && iwb-backup.sh wphtml weekly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh n8n weekly" "$CRON_FILE" || echo "$N8N_WEEKLY_MIN 2 * * 0 . /var/data/state/docker-env.sh && iwb-backup.sh n8n weekly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh rspamd weekly" "$CRON_FILE" || echo "$RSPAMD_WEEKLY_MIN 2 * * 0 . /var/data/state/docker-env.sh && iwb-backup.sh rspamd weekly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh dkim weekly" "$CRON_FILE" || echo "$DKIM_WEEKLY_MIN 3 * * 0 . /var/data/state/docker-env.sh && iwb-backup.sh dkim weekly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh ssl weekly" "$CRON_FILE" || echo "$SSL_WEEKLY_MIN 3 * * 0 . /var/data/state/docker-env.sh && iwb-backup.sh ssl weekly > /dev/null 2>&1" >> "$CRON_FILE"

# Monthly backups (1st of month, window 03:00–03:59)
MAIL_MONTHLY_MIN=$(compute_offset "mail-monthly" 0 60)
POSTFIX_MONTHLY_MIN=$(compute_offset "postfix-monthly" 0 60)
WPDB_MONTHLY_MIN=$(compute_offset "wpdb-monthly" 0 60)
WPHTML_MONTHLY_MIN=$(compute_offset "wphtml-monthly" 0 60)
N8N_MONTHLY_MIN=$(compute_offset "n8n-monthly" 0 60)
RSPAMD_MONTHLY_MIN=$(compute_offset "rspamd-monthly" 0 60)
DKIM_MONTHLY_MIN=$(compute_offset "dkim-monthly" 0 60)
SSL_MONTHLY_MIN=$(compute_offset "ssl-monthly" 0 60)
grep -q "iwb-backup.sh mail monthly" "$CRON_FILE" || echo "$MAIL_MONTHLY_MIN 3 1 * * . /var/data/state/docker-env.sh && iwb-backup.sh mail monthly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh postfix monthly" "$CRON_FILE" || echo "$POSTFIX_MONTHLY_MIN 3 1 * * . /var/data/state/docker-env.sh && iwb-backup.sh postfix monthly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh wpdb monthly" "$CRON_FILE" || echo "$WPDB_MONTHLY_MIN 3 1 * * . /var/data/state/docker-env.sh && iwb-backup.sh wpdb monthly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh wphtml monthly" "$CRON_FILE" || echo "$WPHTML_MONTHLY_MIN 3 1 * * . /var/data/state/docker-env.sh && iwb-backup.sh wphtml monthly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh n8n monthly" "$CRON_FILE" || echo "$N8N_MONTHLY_MIN 3 1 * * . /var/data/state/docker-env.sh && iwb-backup.sh n8n monthly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh rspamd monthly" "$CRON_FILE" || echo "$RSPAMD_MONTHLY_MIN 3 1 * * . /var/data/state/docker-env.sh && iwb-backup.sh rspamd monthly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh dkim monthly" "$CRON_FILE" || echo "$DKIM_MONTHLY_MIN 3 1 * * . /var/data/state/docker-env.sh && iwb-backup.sh dkim monthly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh ssl monthly" "$CRON_FILE" || echo "$SSL_MONTHLY_MIN 3 1 * * . /var/data/state/docker-env.sh && iwb-backup.sh ssl monthly > /dev/null 2>&1" >> "$CRON_FILE"

# Yearly backups (Jan 1st, window 03:00–04:59)
MAIL_YEARLY_MIN=$(compute_offset "mail-yearly" 0 60)
POSTFIX_YEARLY_MIN=$(compute_offset "postfix-yearly" 0 60)
WPDB_YEARLY_MIN=$(compute_offset "wpdb-yearly" 0 60)
WPHTML_YEARLY_MIN=$(compute_offset "wphtml-yearly" 0 60)
N8N_YEARLY_MIN=$(compute_offset "n8n-yearly" 0 60)
RSPAMD_YEARLY_MIN=$(compute_offset "rspamd-yearly" 0 60)
DKIM_YEARLY_MIN=$(compute_offset "dkim-yearly" 0 60)
SSL_YEARLY_MIN=$(compute_offset "ssl-yearly" 0 60)
grep -q "iwb-backup.sh mail yearly" "$CRON_FILE" || echo "$MAIL_YEARLY_MIN 3 1 1 * . /var/data/state/docker-env.sh && iwb-backup.sh mail yearly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh postfix yearly" "$CRON_FILE" || echo "$POSTFIX_YEARLY_MIN 3 1 1 * . /var/data/state/docker-env.sh && iwb-backup.sh postfix yearly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh wpdb yearly" "$CRON_FILE" || echo "$WPDB_YEARLY_MIN 3 1 1 * . /var/data/state/docker-env.sh && iwb-backup.sh wpdb yearly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh wphtml yearly" "$CRON_FILE" || echo "$WPHTML_YEARLY_MIN 3 1 1 * . /var/data/state/docker-env.sh && iwb-backup.sh wphtml yearly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh n8n yearly" "$CRON_FILE" || echo "$N8N_YEARLY_MIN 3 1 1 * . /var/data/state/docker-env.sh && iwb-backup.sh n8n yearly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh rspamd yearly" "$CRON_FILE" || echo "$RSPAMD_YEARLY_MIN 3 1 1 * . /var/data/state/docker-env.sh && iwb-backup.sh rspamd yearly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh dkim yearly" "$CRON_FILE" || echo "$DKIM_YEARLY_MIN 4 1 1 * . /var/data/state/docker-env.sh && iwb-backup.sh dkim yearly > /dev/null 2>&1" >> "$CRON_FILE"
grep -q "iwb-backup.sh ssl yearly" "$CRON_FILE" || echo "$SSL_YEARLY_MIN 4 1 1 * . /var/data/state/docker-env.sh && iwb-backup.sh ssl yearly > /dev/null 2>&1" >> "$CRON_FILE"

#grep -q "iwb-logtest.sh" "$CRON_FILE" || echo "* * * * * . /var/data/state/docker-env.sh && iwb-logtest.sh 2>&1" >> "$CRON_FILE"

## certbot renew
grep -q "/usr/bin/certbot renew --quiet --deploy-hook" "$CRON_FILE" || \
echo "0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook \"/var/setup/scripts/cert-renew-hook.sh\" > /dev/null 2>&1" >> "$CRON_FILE"


# Nightly backup cleanup (randomized minute within 04:00–04:59)
CLEANUP_MIN=$(compute_offset "cleanup-nightly" 0 60)
grep -q "iwb-backup-cleanup.sh all all" "$CRON_FILE" || echo "$CLEANUP_MIN 4 * * * . /var/data/state/docker-env.sh && iwb-backup-cleanup.sh all all > /dev/null 2>&1" >> "$CRON_FILE"


log "Cron jobs configured."

MODULE=$CALL_MODULE
(return 0 2>/dev/null) || exit 0

