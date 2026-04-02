#!/bin/bash
#includes/setup/scripts/setup-mail-barebones.sh

# Replace placeholder with actual domain in postfix-main.cf
echo -e "$IWB_PREFIX Substituting IWB_DOMAIN in postfix-main.cf"
sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" $IWB_CONFIGDIR/mail/postfix/postfix-main-barebones.cf.template > $IWB_CONFIGDIR/mail/postfix/postfix-main-barebones.cf

# Symlink configuration files
echo -e "$IWB_PREFIX Linking config files"
mkdir -p /etc/rsyslog.d
mkdir -p /etc/supervisor/conf.d
mkdir -p /etc/dovecot/sieve-before
ln -sf $IWB_CONFIGDIR/mail/postfix/postfix-main-barebones.cf /etc/postfix/main.cf
ln -sf $IWB_CONFIGDIR/mail/postfix/postfix-master-barebones.cf /etc/postfix/master.cf
ln -sf $IWB_CONFIGDIR/mail/dovecot/dovecot-99-barebones.conf /etc/dovecot/conf.d/99-local.conf
ln -sf $IWB_CONFIGDIR/mail/dovecot/default-spam-filter.sieve /etc/dovecot/sieve-before/00-spam-to-junk.sieve
ln -sf $IWB_CONFIGDIR/system/rsyslogd/rsyslogd-10-postfix.conf /etc/rsyslog.d/10-postfix.conf
ln -sf $IWB_CONFIGDIR/system/supervisord/supervisord-barebones.conf /etc/supervisor/conf.d/supervisord.conf

# Ensure logging directories exist
touch /var/log/dovecot.log /var/log/dovecot-debug.log /var/log/postfix.log
chmod 640 /var/log/dovecot*.log /var/log/postfix.log
chown vmail:vmail /var/log/dovecot*.log || true


# Create user db file if it doesn't exist
USERFILE=/etc/dovecot/users
EXPECTED_USER="$IWB_MAIL_USER@$IWB_DOMAIN"

# Check if user entry exists and is correct
if ! grep -q "^$EXPECTED_USER:" "$USERFILE" 2>/dev/null; then
  echo -e "$IWB_PREFIX Creating or repairing default user: $EXPECTED_USER"
  mkdir -p "/var/mail/vmail/$IWB_DOMAIN/$IWB_MAIL_USER/Maildir"/{cur,new,tmp}
  chown -R vmail:vmail "/var/mail/vmail/$IWB_DOMAIN"

  HASHED_PASS=$(doveadm pw -s SHA512-CRYPT -p "$IWB_MAIL_PASS")
  echo -e "$EXPECTED_USER:$HASHED_PASS:10000:10000::/var/mail/vmail/$IWB_DOMAIN/$IWB_MAIL_USER::" > "$USERFILE"
  chmod 600 "$USERFILE"
fi

# Ensure virtual_alias catch-all is in place
ALIASMAP=/etc/postfix/virtual_alias
EXPECTED_ALIAS="/.*/ ${IWB_MAIL_USER}@${IWB_DOMAIN}"

if ! grep -q "^/.*/" "$ALIASMAP" 2>/dev/null; then
  echo -e "$IWB_PREFIX Creating catch-all alias: $EXPECTED_ALIAS"
  echo -e "$EXPECTED_ALIAS" > "$ALIASMAP"
  chmod 644 "$ALIASMAP"
fi

# Safe exit/return mechanism
(return 0 2>/dev/null) || exit 0
