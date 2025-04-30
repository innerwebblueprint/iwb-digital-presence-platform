#!/bin/bash
# includes/setup/scripts/setup-dkim.sh
# Runs once after startup to generate or restore DKIM key and notify admin

set -e

MODULE="DKIM"

LOG_FILE="/var/log/setup-dkim.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting DKIM setup in the background for $IWB_DOMAIN..."

sleep 10

DKIM_DIR="/var/lib/rspamd/dkim"
DOMAIN="${IWB_DOMAIN}"
SELECTOR="dkim"
DKIM_KEY="${DKIM_DIR}/${DOMAIN}.${SELECTOR}.key"
BACKUP_KEY="${IWB_DKIM_CERT_BACKUP_KEY}"
TMP_BACKUP="/tmp/${DOMAIN}_dkim_certs.tar.gz"

# === Create DKIM directory if it doesn't exist ===
mkdir -p "$DKIM_DIR"

log "Attempting to restore DKIM keys from Storj..."

# === Try restoring existing DKIM key ===
if iwb-restore.sh dkim latest; then
  log "Existing DKIM keys restored successfully."
else
  log "No existing DKIM keys found, generating a new one."
  # === Wait for postfix to become ready ===
  while ! nc -z 127.0.0.1 25; do
    log "Waiting for postfix (port 25)..."
    sleep 4
  done
  # === Wait for rspamd to become ready ===
  while ! nc -z 127.0.0.1 11334; do
    log "Waiting for rspamd (port 11334)..."
    sleep 4
  done
  # === Generate DKIM key ===
  log "Services ready. Generating DKIM keys..."
  rspamadm dkim_keygen -d "$DOMAIN" -s "$SELECTOR" -k "$DKIM_KEY" -b 2048
  log "DKIM keys generated..."

  # === Backup newly generated DKIM key ===
  log "Backing up newly generated DKIM keys..."
  iwb-backup.sh dkim snapshot
fi

chown rspamd:rspamd $DKIM_KEY
chmod 600 $DKIM_KEY

log "DKIM KEY: $DKIM_KEY"
# cat $DKIM_KEY

log "Sending DKIM setup email to $IWB_MAIL_USER@$DOMAIN"

# Determine expected public key file location
DKIM_KEY_DIR="/var/lib/rspamd/dkim"
DKIM_PRIVKEY="${DKIM_KEY_DIR}/${DOMAIN}.${SELECTOR}.key"

# if [ ! -f "$DKIM_PRIVKEY" ]; then
#    # File doesn't exist, safe to generate
#    log "Private key not found, generating new key..."
#    rspamadm dkim_keygen -d "$DOMAIN" -s "$SELECTOR" -k "$DKIM_KEY" -b 2048
# else
#    log "DKIM private key already exists, skipping generation..."
# fi



set +e
#DKIM_PUBKEY=$(rspamadm dkim_keygen -k "$DKIM_PRIVKEY" -s "$SELECTOR" -d "$DOMAIN" 2>/dev/null | grep 'record' | cut -d':' -f2-)

#DKIM_PUBKEY=$(rspamadm dkim_keygen -k "$DKIM_PRIVKEY" -s "$SELECTOR" -d "$DOMAIN" | grep 'record' | cut -d':' -f2-)
#log "TEST TEST TEST $DKIM_PUBKEY"
set -e

# Safety check fallback

if [ -z "${DKIM_PUBKEY:-}" ]; then
  log "Public key not restored, extracting manually"
  DKIM_PUBKEY=""
fi

# Extract public key from private key manually
if [ -z "$DKIM_PUBKEY" ] && [ -f "$DKIM_PRIVKEY" ]; then
  log "Extracting public key"
  DKIM_PUBKEY=$(openssl rsa -in "$DKIM_PRIVKEY" -pubout 2>/dev/null \
    | openssl rsa -RSAPublicKey_in -pubin -outform DER 2>/dev/null \
    | base64 -w0 \
    | sed 's/.*/"v=DKIM1; k=rsa; p=&"/')
fi

# Safety check fallback
DKIM_PUBKEY="${DKIM_PUBKEY:-(could not extract key)}"

# For local tests only when IP not assigned
if [ -z "${PUBLIC_IP:-}" ]; then
  PUBLIC_IP="testing"
fi

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

# --- Send email ---
set -o pipefail

# --- Send email ---
echo -e "$BODY" | mail -s "$SUBJECT" -r "$MAIL_FROM" "$MAIL_TO"

if [ $? -ne 0 ]; then
  log "$ERR_PREFIX Failed to send DKIM email notification to $MAIL_TO"
  return 1
else
  log "email sent to $IWB_MAIL_USER@$DOMAIN please check for required DNS records"
fi

log "Done." 


(return 0 2>/dev/null) || exit 0