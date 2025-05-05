#!/bin/bash
# includes/setup/scripts/setup-webserver.sh

set -e

MODULE="PRE_WEB"

log "Setting up web server environment..."

# === Create webroot directories ===
mkdir -p "$IWB_WEB_WP"
mkdir -p "$IWB_WEB_POSTFIX"
mkdir -p "$IWB_WEB_WEBMAIL"

# === Process "coming soon" page ===
COMING_SOON_TEMPLATE="$IWB_HTML_TEMPLATE_DIR/index.html.template"
COMING_SOON_OUTPUT="$IWB_HTML_TEMPLATE_DIR/index.html"

if [ ! -f "$COMING_SOON_TEMPLATE" ]; then
  echo -e "$IWB_PREFIX $ERR_PREFIX Missing coming soon template: $COMING_SOON_TEMPLATE"
  return 1
fi

if ! sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" "$COMING_SOON_TEMPLATE" > "$COMING_SOON_OUTPUT"; then
  echo -e "$IWB_PREFIX $ERR_PREFIX Failed to render coming soon page from template."
  return 1
else
  echo -e "$IWB_PREFIX Coming soon page rendered for $IWB_DOMAIN"
fi

# === Link to all service webroots ===
ln -sf "$COMING_SOON_OUTPUT" "$IWB_WEB_WP/index.html"
log "Linked coming soon page for $IWB_WEB_WP"

ln -sf "$COMING_SOON_OUTPUT" "$IWB_WEB_POSTFIX/index.html"
log "Linked coming soon page for $IWB_WEB_POSTFIX"

ln -sf "$COMING_SOON_OUTPUT" "$IWB_WEB_WEBMAIL/index.html"
log "Linked coming soon page for $IWB_WEB_WEBMAIL"

# === PHP-FPM Configuration ===
echo -e "$IWB_PREFIX Linking PHP-FPM configuration..."
mkdir -p "$(dirname "$IWB_PHP_POOL_CONF")"

ln -sf "$IWB_CONFIGDIR/php/php-fpm.conf" "$IWB_PHP_FPM_CONF"
ln -sf "$IWB_CONFIGDIR/php/www.conf" "$IWB_PHP_POOL_CONF"
ln -sf "$IWB_CONFIGDIR/php/99-php_custom_overrides.ini" "$IWB_PHP_INI_CONF"

log "Web server setup complete"

(return 0 2>/dev/null) || exit 0