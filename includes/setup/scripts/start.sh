#!/bin/bash
# includes/setup/scripts/start.sh

set -e

# Set some constants
# Visual prefixes
# Define colored IWB prefix
# escape sequences using real escape characters
export IWB_RED=$(printf '\033[0;31m')
export IWB_GREEN=$(printf '\033[0;32m')
export IWB_BLUE=$(printf '\033[0;34m')
export IWB_RESET=$(printf '\033[0m')

export IWB_PREFIX="${IWB_GREEN}[${IWB_RED}I${IWB_GREEN}W${IWB_BLUE}B${IWB_GREEN}]${IWB_RESET}"
export ERR_PREFIX="${IWB_RED}ERROR${IWB_RESET}"

export SCRIPTSDIR="/var/setup/scripts"
export CONFIGDIR="/var/setup/configs"

# === Required environment checks ===
if [ -z "$IWB_DOMAIN" ]; then
  echo -e "$IWB_PREFIX $ERR_PREFIX: IWB_DOMAIN environment variable not set. Aborting startup."
  exit 1
fi

if [ -z "$MAIL_USER" ]; then
  echo -e "$IWB_PREFIX $ERR_PREFIX: MAIL_USER environment variable not set. Aborting startup."
  exit 1
fi

if [ -z "$MAIL_PASS" ]; then
    echo -e "$IWB_PREFIX $ERR_PREFIX! MAIL_PASS not set. Aborting"
    exit 1
fi

echo -e "$IWB_PREFIX Starting container services... in ${IWB_GREEN}$IWB_MODE${IWB_RESET} mode"

# Run setup based on IWB_MODE
if [[ "$IWB_MODE" == "bare-bones-email-only" ]]; then
  echo -e "${IWB_PREFIX} Running bare-bones mail setup..."
  source $SCRIPTSDIR/setup-mail-barebones.sh
elif [[ "$IWB_MODE" == "full" ]]; then
  echo -e "${IWB_PREFIX} Running full setup..."
  source $SCRIPTSDIR/setup-full.sh
else
  echo -e "${IWB_PREFIX} ${ERROR_PREFIX} Unknown IWB_MODE: $IWB_MODE"
  exit 1
fi

# Clean up stale supervisord socket if it exists
[ -e /run/supervisord.sock ] && echo -e "$IWB_PREFIX Unlinking stale socket /run/supervisord.sock" && rm -f /run/supervisord.sock

# Start supervisord in foreground
echo -e "$IWB_PREFIX Launching supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf