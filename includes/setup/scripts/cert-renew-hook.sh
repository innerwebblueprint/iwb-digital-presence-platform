#!/bin/bash
# includes/setup/scripts/cert-renew-hook.sh

set -e

echo "[IWB] Certificates renewed, reloading services..."

# Reload services individually so one failure doesn't stop others
/usr/bin/supervisorctl restart nginx || true
/usr/bin/supervisorctl restart postfix || true
/usr/bin/supervisorctl restart dovecot || true

# Backup to Storj
/var/setup/scripts/iwb-backup ssl snapshot
