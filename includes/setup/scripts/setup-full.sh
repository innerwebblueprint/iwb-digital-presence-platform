#!/bin/bash
#includes/setup/scripts/setup-mail-full.sh

echo -e "${IWB_PREFIX} Running full setup..."

# Setup Storj Access
if [ "$STORJ_ENABLED" == "true" ]; then
  echo -e "$IWB_PREFIX Initializing Storj backup system..."
  mkdir -p ~/.local/share/storj/uplink
  uplink setup --access "$STORJ_ACCESS_KEY"
fi

# Setting up Niginx 
echo -e "$IWB_PREFIX Creating nginx configs for $IWB_DOMAIN.conf"
#sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" /var/mail/conf/nginx.conf.template > /etc/nginx/nginx.conf


# Symlink configuration files
echo -e "$IWB_PREFIX Linking config files"
mkdir -p /etc/rsyslog.d
mkdir -p /etc/supervisor/conf.d
ln -sf $CONFIGDIR/mail/postfix/postfix-main-full.cf /etc/postfix/main.cf
ln -sf $CONFIGDIR/mail/postfix/postfix-master-full.cf /etc/postfix/master.cf
ln -sf $CONFIGDIR/mail/dovecot/dovecot-99-full.conf /etc/dovecot/conf.d/99-local.conf
ln -sf $CONFIGDIR/system/rsyslogd/rsyslogd-10-postfix.conf /etc/rsyslog.d/10-postfix.conf
ln -sf $CONFIGDIR/system/supervisord/supervisord-full.conf /etc/supervisor/conf.d/supervisord.conf



#mkdir -p /var/www/certbot

