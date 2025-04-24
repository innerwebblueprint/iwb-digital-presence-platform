#!/bin/bash
# includes/setup/scripts/setup-dkim.sh
# Runs once after startup to generate or restore DKIM key and notify admin

set -e

LOG_FILE="/var/log/setup-dkim.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  echo -e "$IWB_PREFIX $IWB_BLUE DKIM $IWB_RESET $1"
}

log "Starting DKIM setup in the background for $IWB_DOMAIN..."

DKIM_DIR="/var/lib/rspamd/dkim"
DOMAIN="${IWB_DOMAIN}"
SELECTOR="dkim"
DKIM_KEY="${DKIM_DIR}/${DOMAIN}.${SELECTOR}.key"
BACKUP_KEY="${IWB_DKIM_CERT_BACKUP_KEY}"
TMP_BACKUP="/tmp/${DOMAIN}_dkim_certs.tar.gz"

# Create DKIM directory if not exists
mkdir -p "$DKIM_DIR"

log "[DKIM] Attempting to restore DKIM keys from Storj..."
sleep 4
if uplink cp "$BACKUP_KEY" "$TMP_BACKUP"; then
  log "Restored archive found. Extracting..."
  tar -xzvf "$TMP_BACKUP" -C "$DKIM_DIR"
else
  log "Waiting for rspamd and postfix to be available..."

  # Wait for rspamd (check socket or port)
  while ! nc -z 127.0.0.1 11334; do
    log "Waiting for rspamd (port 11334)..."
    sleep 4
  done

  # Wait for postfix (check port 25 open locally)
  while ! nc -z 127.0.0.1 25; do
    log "Waiting for postfix (port 25)..."
    sleep 4
  done

  log "Services ready. Starting DKIM setup..."

  echo -e "$IWB_PREFIX [DKIM] No backup found. Generating new DKIM key..."
  rspamadm dkim_keygen -d "$DOMAIN" -s "$SELECTOR" -k "$DKIM_KEY" -b 2048
  echo -e "$IWB_PREFIX [DKIM] Archiving and uploading DKIM key to Storj..."
  tar -czvf "$TMP_BACKUP" -C "$DKIM_DIR" .
  uplink cp "$TMP_BACKUP" "$BACKUP_KEY"
fi

chown rspamd:rspamd $DKIM_KEY
chmod 600 $DKIM_KEY


# Determine expected public key file location
DKIM_KEY_DIR="/var/lib/rspamd/dkim"
DKIM_PRIVKEY="${DKIM_KEY_DIR}/${DOMAIN}.${SELECTOR}.key"
DKIM_PUBKEY=$(rspamadm dkim_keygen -k "$DKIM_PRIVKEY" -s "$SELECTOR" -d "$DOMAIN" 2>/dev/null | grep 'record' | cut -d':' -f2-)

# Fallback if keygen doesn't output (already exists), extract manually
if [ -z "$DKIM_PUBKEY" ] && [ -f "$DKIM_PRIVKEY" ]; then
  DKIM_PUBKEY=$(openssl rsa -in "$DKIM_PRIVKEY" -pubout 2>/dev/null \
    | openssl rsa -RSAPublicKey_in -pubin -outform DER 2>/dev/null \
    | base64 -w0 \
    | sed 's/.*/"v=DKIM1; k=rsa; p=&"/')
fi

# Safety check fallback
DKIM_PUBKEY="${DKIM_PUBKEY:-(could not extract key)}"

# Compose email (same as before, just inserting DKIM_PUBKEY properly)
MAIL_FROM="${IWB_MAIL_USER}@$DOMAIN"
MAIL_TO="$MAIL_FROM"
SUBJECT="✅ DKIM + SPF + DMARC DNS Setup Instructions for $DOMAIN"

BODY=$(cat <<EOF
Hello!

Your email server at $DOMAIN is now configured with DKIM signing, and this message was sent from that server.

To fully enable outbound email authentication (and improve deliverability), please add the following **DNS records** to your domain ($DOMAIN):

---

🔐 DKIM (DomainKeys Identified Mail)
Record Type:  TXT  
Record Name:  ${SELECTOR}._domainkey.$DOMAIN  
Record Value: $DKIM_PUBKEY

✉️ SPF (Sender Policy Framework)
Record Type:  TXT  
Record Name:  $DOMAIN  
Record Value: v=spf1 ip4:$PUBLIC_IP -all

📊 DMARC (Domain-based Message Authentication, Reporting and Conformance)
Record Type:  TXT  
Record Name:  _dmarc.$DOMAIN  
Record Value: v=DMARC1; p=quarantine; rua=mailto:$MAIL_FROM; ruf=mailto:$MAIL_FROM; sp=none; adkim=r; aspf=r

---

📘 **What These Do**
- **DKIM** adds a digital signature to outgoing mail proving it was sent from you.
- **SPF** helps mail servers verify your server is allowed to send email for your domain.
- **DMARC** tells recipients how to handle mail that fails DKIM or SPF checks, and where to send reports.

If you have any questions, feel free to reply to this message (you're receiving it at your admin address).

Blessings on your emails ✉️✨

– Your IWB Server 🌐
EOF
)

echo -e "$BODY" | mail -s "$SUBJECT" -r "$MAIL_FROM" "$MAIL_TO"

log "Done." 

exit 0