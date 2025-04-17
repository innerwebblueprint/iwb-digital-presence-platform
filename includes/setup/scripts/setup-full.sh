#!/bin/bash
#includes/setup/scripts/setup-mail-full.sh

# Setup Storj Access
if [ "$PERSISTENT_STORAGE" == "storj" ]; then
  echo -e "$IWB_PREFIX Initializing Storj backup system..."
  
  mkdir -p /root/.config/storj/uplink

  cat > /root/.config/storj/uplink/config.ini <<EOF
[analytics]
enabled = false

[metrics]
addr =
EOF

  echo -e "$IWB_PREFIX config.ini written to suppress analytics prompt"

  if uplink access import default "$STORJ_GRANT" --force; then
    uplink access use default
    echo -e "$IWB_PREFIX Storj access imported and set to default"
  else
    echo -e "$IWB_PREFIX $ERR_PREFIX Failed to import Storj access grant"
    exit 1
  fi

#  echo -e "$IWB_PREFIX DEBUG: Dumping generated access.json"
#  cat /root/.config/storj/uplink/access.json
#  uplink version

  echo -e "$IWB_PREFIX Verifying Storj access for bucket: $STORJ_WPOPS_BUCKET"
  if ! uplink ls "sj://${STORJ_WPOPS_BUCKET}/"; then
    echo -e "$IWB_PREFIX $ERR_PREFIX Failed to verify Storj access. Check STORJ_GRANT and STORJ_WPOPS_BUCKET values."
    exit 1
  else
    echo -e "$IWB_PREFIX Storj access verified successfully for bucket: $STORJ_WPOPS_BUCKET"
  fi

fi

# Setting up Web Servers
echo -e "${IWB_PREFIX} Ensuring web root directories for nginx..."

# Replace {{IWB_DOMAIN}} in the coming soon page
COMING_SOON_TEMPLATE="/var/setup/html/index.html.template"
COMING_SOON_OUTPUT="/var/setup/html/index.html"

echo -e "$IWB_PREFIX Checking for file: $COMING_SOON_TEMPLATE"
ls -l "$COMING_SOON_TEMPLATE" || echo -e "$IWB_PREFIX $ERR_PREFIX Template file not found!"


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

for DIR in /var/www/postfixadmin/public /var/www/webmail/public; do
  mkdir -p "$DIR"
  if [ ! -f "$DIR/index.html" ]; then
    echo -e "${IWB_PREFIX} Linked coming soon page to $DIR/index.html"
    ln -sf /var/includes/html/index.html $DIR/index.html
  fi
done

# Setup Nginx virtual host templates
echo -e "${IWB_PREFIX} Configuring Nginx site templates..."
NGINX_TEMPLATE_DIR="/var/setup/configs/http/nginx/sites-available"
NGINX_TARGET_DIR="/etc/nginx/http.d"

mkdir -p "$NGINX_TARGET_DIR"
# Replace {{IWB_DOMAIN}} in each template and symlink into the Nginx directory
for SITE in default mail webmail; do
  TEMPLATE_FILE="$NGINX_TEMPLATE_DIR/${SITE}.conf.template"
  OUTPUT_FILE="$NGINX_TEMPLATE_DIR/${SITE}.conf"
  TARGET_LINK="$NGINX_TARGET_DIR/${SITE}.conf"

  if [ -f "$TEMPLATE_FILE" ]; then
    sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"
    ln -sf "$OUTPUT_FILE" "$TARGET_LINK"
    echo -e "${IWB_PREFIX} Linked $SITE.conf for $IWB_DOMAIN"
  else
    echo -e "${IWB_PREFIX} ERROR: Missing template: $TEMPLATE_FILE"
  fi
done

echo -e "$IWB_PREFIX Linking PHP-FPM configuration..."

mkdir -p /etc/php81/php-fpm.d

ln -sf /var/setup/configs/php/php-fpm.conf /etc/php81/php-fpm.conf
ln -sf /var/setup/configs/php/www.conf /etc/php81/php-fpm.d/www.conf

# Handle SSL certificate setup via Let's Encrypt
echo -e "${IWB_PREFIX} Preparing certificate setup for $IWB_DOMAIN..."
source /var/setup/scripts/cert-setup.sh

# Setting up eMail
echo -e "$IWB_PREFIX Setting up eMail"
echo -e "$IWB_PREFIX Creating Postfix configs"
sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" $CONFIGDIR/mail/postfix/postfix-main-full.cf.template > $CONFIGDIR/mail/postfix/postfix-main.cf

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

# Safe exit/return mechanism
(return 0 2>/dev/null) || exit 0

