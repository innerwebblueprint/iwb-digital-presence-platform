#!/bin/bash
# includes/setup/scripts/cert-renew-hook.sh

set -e

echo "[IWB] Certificates renewed, reloading services..."

# Reload services to use new certs
supervisorctl restart nginx postfix dovecot || true

# Backup to Storj
source /var/setup/scripts/storj-backup.sh

