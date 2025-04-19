#!/bin/bash
#includes/setup/scripts/setup-mail-full.sh

# Setting up Web Servers
echo -e "${IWB_PREFIX} Ensuring web root directories for nginx..."

IWB_WEB_WP=/var/www/html/wordpress
IWB_WEB_POSTFIX=/var/www/html/postfixadmin/public
IWB_WEB_WEBMAIL=/var/www/html/webmail/public
mkdir -p $IWB_WEB_WP
mkdir -p $IWB_WEB_POSTFIX
mkdir -p $IWB_WEB_WEBMAIL

# Process comming soon template {{IWB_DOMAIN}}
COMING_SOON_TEMPLATE="/var/setup/html/index.html.template"
COMING_SOON_OUTPUT="/var/setup/html/index.html"

if [ ! -f "$COMING_SOON_TEMPLATE" ]; then
  echo -e "$IWB_PREFIX $ERR_PREFIX Missing coming soon template: $COMING_SOON_TEMPLATE"
  exit 1
fi

if ! sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" "$COMING_SOON_TEMPLATE" > "$COMING_SOON_OUTPUT"; then
  echo -e "$IWB_PREFIX $ERR_PREFIX Failed to render coming soon page from template."
  exit 1
else
  echo -e "$IWB_PREFIX Coming soon page rendered for $IWB_DOMAIN"
fi

echo -e "${IWB_PREFIX} Linked coming soon page for $IWB_WEB_WP"
ln -sf $COMING_SOON_OUTPUT $IWB_WEB_WP/index.html

echo -e "${IWB_PREFIX} Linked coming soon page for $IWB_WEB_POSTFIX root"
ln -sf $COMING_SOON_OUTPUT $IWB_WEB_POSTFIX/index.html

echo -e "${IWB_PREFIX} Linked coming soon page for $IWB_WEB_WEBMAIL root"
ln -sf $COMING_SOON_OUTPUT $IWB_WEB_WEBMAIL/index.html

echo -e "$IWB_PREFIX Linking PHP-FPM configuration..."

mkdir -p /etc/php81/php-fpm.d

ln -sf /var/setup/configs/php/php-fpm.conf /etc/php81/php-fpm.conf
ln -sf /var/setup/configs/php/www.conf /etc/php81/php-fpm.d/www.conf

# Handle SSL certificate setup via Let's Encrypt
echo -e "${IWB_PREFIX} Preparing certificate setup for $IWB_DOMAIN..."

if ! source /var/setup/scripts/cert-setup.sh; then
  echo -e "$IWB_PREFIX $ERR_PREFIX Certificate setup failed. Aborting container startup."
  exit 1
fi

# Setup Nginx virtual host templates for SSL (we exit if we fail to get certs so this is safe)
echo -e "$IWB_PREFIX Processing and linking SSL-enabled Nginx configs..."

SSL_TEMPLATE_DIR="$CONFIGDIR/http/nginx/sites-available"
NGINX_CONF_DIR="/etc/nginx/http.d"

# Let's empty that directory to make sure nothing is in there from before
rm -rf "$NGINX_CONF_DIR" 
mkdir -p "$NGINX_CONF_DIR"

for TEMPLATE in "$SSL_TEMPLATE_DIR"/*ssl*.conf.template; do
  if [ -f "$TEMPLATE" ]; then
    BASENAME=$(basename "$TEMPLATE" .template)   # e.g. default-ssl.conf
    OUTPUT="$SSL_TEMPLATE_DIR/$BASENAME"
    LINK_TARGET="$NGINX_CONF_DIR/$BASENAME"

    sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" "$TEMPLATE" > "$OUTPUT"
    ln -sf "$OUTPUT" "$LINK_TARGET"

    echo -e "$IWB_PREFIX Linked SSL config: $BASENAME"
  else
    echo -e "$IWB_PREFIX $ERR_PREFIX No matching SSL templates found in $SSL_TEMPLATE_DIR"
  fi
done

# Setting up eMail
echo -e "$IWB_PREFIX Setting up eMail"

echo -e "$IWB_PREFIX Creating Postfix configs"
sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" $CONFIGDIR/mail/postfix/postfix-main-full.cf.template > $CONFIGDIR/mail/postfix/postfix-main-full.cf

echo -e "$IWB_PREFIX Creating Dovecot configs"
sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" "$CONFIGDIR/mail/dovecot/dovecot-99-full.conf.template" > "$CONFIGDIR/mail/dovecot/dovecot-99-full.conf"


# Symlink configuration files
echo -e "$IWB_PREFIX Linking config files"
mkdir -p /etc/rsyslog.d
mkdir -p /etc/supervisor/conf.d
ln -sf $CONFIGDIR/mail/postfix/postfix-main-full.cf /etc/postfix/main.cf
ln -sf $CONFIGDIR/mail/postfix/postfix-master-full.cf /etc/postfix/master.cf
ln -sf $CONFIGDIR/mail/dovecot/dovecot-99-full.conf /etc/dovecot/conf.d/99-local.conf
ln -sf $CONFIGDIR/system/rsyslogd/rsyslogd-10-postfix.conf /etc/rsyslog.d/10-postfix.conf
ln -sf $CONFIGDIR/system/supervisord/supervisord-full.conf /etc/supervisor/conf.d/supervisord.conf


# Safe exit/return mechanism
(return 0 2>/dev/null) || exit 0

