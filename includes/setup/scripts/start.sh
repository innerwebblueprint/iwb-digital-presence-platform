#!/bin/bash
# includes/setup/scripts/start.sh

set -e

# Load IWB environment
source /var/setup/scripts/setup-env.sh

echo -e "$IWB_PREFIX Starting container services... in ${IWB_GREEN}$IWB_MODE${IWB_RESET} mode"

# Run setup based on IWB_MODE
if [[ "$IWB_MODE" == "bare-bones-email-only" ]]; then
  echo -e "${IWB_PREFIX} Running bare-bones mail setup..."
  source $IWB_SCRIPTSDIR/setup-mail-barebones.sh
elif [[ "$IWB_MODE" == "full" ]]; then
  # Running Full setup...
  echo -e "${IWB_PREFIX} Running full setup..."
  if ! source $IWB_SCRIPTSDIR/setup-full.sh; then
    echo -e "$IWB_PREFIX $ERR_PREFIX Full setup failed. Aborting."
    
    echo "$IWB_PREFIX Holding container open for debug..."
    tail -f /dev/null
    exit 0
  fi
else
  echo -e "${IWB_PREFIX} ${ERROR_PREFIX} Unknown IWB_MODE: $IWB_MODE"
  exit 1
fi

# Setup local DNS cache to work around musl DNS resolver limitations
echo -e "$IWB_PREFIX Setting up dnsmasq local resolver..."

# Setup dnsmasq config
mkdir -p /etc
ln -sf "$IWB_CONFIGDIR/system/dnsmasq/dnsmasq.conf" /etc/dnsmasq.conf

# Clear /etc/resolv.conf and point to local DNS cache
echo "nameserver 127.0.0.1" > /etc/resolv.conf


# Clean up stale supervisord socket if it exists
[ -e /run/supervisord.sock ] && echo -e "$IWB_PREFIX Unlinking stale socket /run/supervisord.sock" && rm -f /run/supervisord.sock

# Start supervisord in foreground
echo -e "$IWB_PREFIX Launching supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf