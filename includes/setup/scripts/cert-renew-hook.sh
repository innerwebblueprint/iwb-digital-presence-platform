#!/bin/bash
# includes/setup/scripts/cert-renew-hook.sh

set -e

# Load environment variables
source /var/setup/scripts/setup-env.sh

log "Certificates renewed, reloading services..."

# Reload services individually so one failure doesn't stop others
/usr/bin/supervisorctl restart nginx || true
/usr/bin/supervisorctl restart postfix || true
/usr/bin/supervisorctl restart dovecot || true

log "Backing up renewed certificates to cloud storage..."
# Backup to Storj with full path
/var/setup/scripts/backup/iwb-backup.sh ssl snapshot

if [ $? -eq 0 ]; then
  log "SSL certificate backup completed successfully"
  
  # Send notification email
  RENEWAL_DATE=$(date +"%Y-%m-%d %H:%M:%S %Z")
  CERT_EXPIRY=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/$IWB_DOMAIN/cert.pem | cut -d= -f2)
  
  cat <<EOF | /usr/sbin/sendmail -t
To: $IWB_MAIL_USER@$IWB_DOMAIN
From: admin@$IWB_DOMAIN
Subject: SSL Certificate Renewed - $IWB_DOMAIN

SSL Certificate Renewal Notification
=====================================

Domain: $IWB_DOMAIN
Renewal Date: $RENEWAL_DATE
Certificate Expires: $CERT_EXPIRY

The SSL certificate has been automatically renewed and backed up to cloud storage.

Services restarted:
- Nginx (web server)
- Postfix (mail server)
- Dovecot (IMAP/POP3)

Backup location: ssl/snapshot/

--
IWB Digital Presence Platform
Automated Certificate Management
EOF

  log "Renewal notification email sent to $IWB_MAIL_USER@$IWB_DOMAIN"
else
  log "$ERR_PREFIX SSL certificate backup failed!"
fi
