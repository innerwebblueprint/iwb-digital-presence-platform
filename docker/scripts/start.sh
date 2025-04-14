#!/bin/bash
# docker/scripts/start.sh

set -e

# Visual prefixes
IWB_PREFIX="\033[0;32m[\033[0;31mI\033[0;32mW\033[0;34mB\033[0;32m]\033[0m"
ERR_PREFIX="\033[0;31mERROR\033[0m"

# === Required environment checks ===
if [ -z "$MAIL_DOMAIN" ]; then
  echo "$IWB_PREFIX $ERR_PREFIX: MAIL_DOMAIN environment variable not set. Aborting startup."
  exit 1
fi

if [ -z "$MAIL_USER" ]; then
  echo "$IWB_PREFIX $ERR_PREFIX: MAIL_USER environment variable not set. Aborting startup."
  exit 1
fi


echo "$IWB_PREFIX Starting container services..."

# Replace placeholder with actual domain in postfix-main.cf
echo "$IWB_PREFIX Substituting MAIL_DOMAIN in postfix-main.cf"
#sed "s|{{MAIL_DOMAIN}}|$MAIL_DOMAIN|g" /var/mail/conf/postfix-main.cf > /etc/postfix/main.cf
sed "s|{{MAIL_DOMAIN}}|$MAIL_DOMAIN|g" /var/mail/conf/postfix-main.cf.template > /var/mail/conf/postfix-main.cf

# Symlink configuration files
echo "$IWB_PREFIX Linking config files"
mkdir -p /etc/rsyslog.d
ln -sf /var/mail/conf/postfix-main.cf /etc/postfix/main.cf
ln -sf /var/mail/conf/postfix-master.cf /etc/postfix/master.cf
ln -sf /var/mail/conf/dovecot-99-local.conf /etc/dovecot/conf.d/99-local.conf
ln -sf /var/mail/conf/rsyslogd-10-postfix.conf /etc/rsyslog.d/10-postfix.conf
ln -sf /var/mail/conf/supervisord.conf /etc/supervisor/conf.d/supervisord.conf


# Ensure logging directories exist
touch /var/log/dovecot.log /var/log/dovecot-debug.log /var/log/postfix.log
chmod 640 /var/log/dovecot*.log /var/log/postfix.log
chown vmail:vmail /var/log/dovecot*.log || true


# Create user db file if it doesn't exist
USERFILE=/etc/dovecot/users
EXPECTED_USER="$MAIL_USER@$MAIL_DOMAIN"

# Check if user entry exists and is correct
if ! grep -q "^$EXPECTED_USER:" "$USERFILE" 2>/dev/null; then
  echo "$IWB_PREFIX Creating or repairing default user: $EXPECTED_USER"
  mkdir -p "/var/mail/vmail/$MAIL_DOMAIN/$MAIL_USER/Maildir"/{cur,new,tmp}
  chown -R vmail:vmail "/var/mail/vmail/$MAIL_DOMAIN"

  if [ -z "$MAIL_PASS" ]; then
    echo "$IWB_PREFIX $ERR_PREFIX! MAIL_PASS not set. Aborting"
    exit 1
  fi

  HASHED_PASS=$(doveadm pw -s SHA512-CRYPT -p "$MAIL_PASS")
  echo "$EXPECTED_USER:$HASHED_PASS:10000:10000::/var/mail/vmail/$MAIL_DOMAIN/$MAIL_USER::" > "$USERFILE"
  chmod 600 "$USERFILE"
fi

# Ensure virtual_alias catch-all is in place
ALIASMAP=/etc/postfix/virtual_alias
EXPECTED_ALIAS="/.*/ ${MAIL_USER}@${MAIL_DOMAIN}"

if ! grep -q "^/.*/" "$ALIASMAP" 2>/dev/null; then
  echo "$IWB_PREFIX Creating catch-all alias: $EXPECTED_ALIAS"
  echo "$EXPECTED_ALIAS" > "$ALIASMAP"
  chmod 644 "$ALIASMAP"
fi

# Clean up stale supervisord socket if it exists
[ -e /run/supervisord.sock ] && echo "$IWB_PREFIX Unlinking stale socket /run/supervisord.sock" && rm -f /run/supervisord.sock

# Start supervisord in foreground
echo "$IWB_PREFIX Launching supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf