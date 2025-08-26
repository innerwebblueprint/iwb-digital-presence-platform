#!/bin/bash
# includes/setup/scripts/setup-wordpress.sh
set -e

log "Beginning WordPress setup for domain: ${IWB_DOMAIN}"

WP_ROOT="/var/www/html/wordpress"
WP_CONFIG_TEMPLATE="/var/setup/configs/wordpress/wp-config-docker.php"
WP_CONFIG_TARGET="${WP_ROOT}/wp-config.php"
WEBMAIL_USER="webmaster@${IWB_DOMAIN}"
TEMP_PASS_FILE="/tmp/wp-admin-pass.txt"

# === Ensure DB user always exists
log "Ensure database and user '${IWB_WP_MYSQL_USER}' exist..."

mariadb -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${IWB_WP_MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${IWB_WP_MYSQL_USER}'@'localhost' IDENTIFIED BY '${IWB_WP_MYSQL_PASSWORD}';
ALTER USER '${IWB_WP_MYSQL_USER}'@'localhost' IDENTIFIED BY '${IWB_WP_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${IWB_WP_MYSQL_DATABASE}\`.* TO '${IWB_WP_MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

OUTPUT=$(mariadb -u root -p"$IWB_MYSQL_ROOT_PASSWORD" -e "SELECT user FROM mysql.user WHERE user = '$IWB_WP_MYSQL_USER';" 2>&1)
log "MySQL user check output:\n$OUTPUT"


# Default: assume no restore
IWB_WORDPRESS_RESTORED="false"

# === 1. Attempt to restore from backup ===
if iwb-restore.sh wphtml && iwb-restore.sh wpdb; then
  log "WordPress restored from backup."
  IWB_WORDPRESS_RESTORED="true"
fi

# === 3. Fresh install if no restore ===
if [ "$IWB_WORDPRESS_RESTORED" != "true" ]; then
  log "No backup found — initializing fresh WordPress installation."

  # Prepare WordPress directory
  mkdir -p "$WP_ROOT"
  cd "$WP_ROOT"

  log "Downloading latest WordPress..."
  wp core download --locale=en_US --path="$WP_ROOT" --allow-root

  # Copy wp-config template
  log "Generating wp-config.php..."
  cp "$WP_CONFIG_TEMPLATE" "$WP_CONFIG_TARGET"

  # Generate secure password
  IWB_WP_ADMIN_PASSWORD="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20)"
  echo "$IWB_WP_ADMIN_PASSWORD" > "$TEMP_PASS_FILE"

  # Install WordPress
  log "Installing WordPress..."
  wp core install \
    --url="$IWB_WP_SITEURL" \
    --title="Welcome to $IWB_DOMAIN" \
    --admin_user="$IWB_WP_ADMIN_USER" \
    --admin_password="$IWB_WP_ADMIN_PASSWORD" \
    --admin_email="$WEBMAIL_USER" \
    --skip-email \
    --path="$WP_ROOT" \
    --allow-root

  OUTPUT=$(mariadb -u root -p"$IWB_MYSQL_ROOT_PASSWORD" -e "SELECT user FROM mysql.user WHERE user = '$IWB_WP_MYSQL_USER';" 2>&1)

  log "MySQL user check output:\n$OUTPUT"

  log "WordPress fresh install completed successfully."
  # Launch WP admin email sending in background
  source /var/setup/scripts/send-wp-admin-email.sh &
fi

# File permissions
chown -R nginx:nginx "$WP_ROOT"
if [ -f /var/www/html/wordpress/index.html ]; then
  rm /var/www/html/wordpress/index.html
  log "Removed existing index.html placeholder."
fi


(return 0 2>/dev/null) || exit 0
