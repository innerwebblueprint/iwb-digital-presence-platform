#!/bin/bash
# includes/setup/scripts/start.sh

set -e


# Load IWB environment
MODULE="START"
source /var/setup/scripts/setup-env.sh

log "Starting container services... in ${IWB_GREEN}$IWB_MODE${IWB_RESET} mode"

# Save all environment variables (including special characters)
mkdir -p /var/data/state
printenv | awk -F= '{print "export " "\""$1"\"""=""\""$2"\"" }' > /var/data/state/docker-env.sh
chmod +x /var/data/state/docker-env.sh

# Make iwb-backup.sh easily executable
ln -s /var/setup/scripts/backup/iwb-backup.sh /usr/local/bin/iwb-backup.sh
chmod +x /usr/local/bin/iwb-backup.sh
ln -s /var/setup/scripts/backup/iwb-restore.sh /usr/local/bin/iwb-restore.sh
chmod +x /usr/local/bin/iwb-restore.sh

## Log testing to test cron and debug
ln -s /var/setup/scripts/backup/iwb-logtest.sh /usr/local/bin/iwb-logtest.sh
chmod +x /usr/local/bin/iwb-logtest.sh

# Run setup based on IWB_MODE
if [[ "$IWB_MODE" == "bare-bones-email-only" ]]; then
  log "Running bare-bones mail setup..."
  source $IWB_SCRIPTSDIR/setup-mail-barebones.sh
elif [[ "$IWB_MODE" == "full" ]]; then
  # Running Full setup...
  log "Running full setup..."
  if ! source $IWB_SCRIPTSDIR/setup-full.sh; then
    echo -e "$IWB_PREFIX $ERR_PREFIX Full setup failed. Aborting."
    
    echo "$IWB_PREFIX Holding container open for debug..."
    tail -f /dev/null
    exit 0
  fi
else
  log "${ERROR_PREFIX} Unknown IWB_MODE: $IWB_MODE"
  exit 1
fi

# Setup local DNS cache to work around musl DNS resolver limitations
# Started my supervisord
log "Setting up dnsmasq local resolver..."
ln -sf "$IWB_CONFIGDIR/system/dnsmasq/dnsmasq.conf" /etc/dnsmasq.conf
# Clear /etc/resolv.conf and point to local DNS cache
echo "nameserver 127.0.0.1" > /etc/resolv.conf


# Clean up stale supervisord socket if it exists
[ -e /run/supervisord.sock ] && echo -e "$IWB_PREFIX Unlinking stale socket /run/supervisord.sock" && rm -f /run/supervisord.sock

log "Setting up cron service..."
source /var/setup/scripts/setup-cron.sh


# Launch DKIM setup in background
source /var/setup/scripts/setup-dkim.sh &

sleep 2


# Start supervisord in foreground
echo -e "$IWB_PREFIX Launching supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf