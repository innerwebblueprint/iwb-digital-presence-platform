#!/bin/bash
# includes/setup/scripts/postfixadmin-setup.sh

set -e


MODULE="POSTFIX"

log "Starting PostfixAdmin setup..."
mkdir -p "$IWB_STATE_DIR"

# === Skip if already done ===
if [ -f "$IWB_POSTFIXADMIN_CONFIGURED_FLAG" ] && [ -f "$IWB_POSTFIXADMIN_SCHEMA_FLAG" ]; then
  log "PostfixAdmin already configured and schema initialized. Skipping."
  return 0
fi
 
# === Generate config.local.php from template ===
log "Generating config.local.php..."
mkdir -p "$(dirname "$IWB_POSTFIXADMIN_CONFIG_OUT")"
cp "$IWB_POSTFIXADMIN_TEMPLATE" "$IWB_POSTFIXADMIN_CONFIG_OUT"

IWB_POSTFIXADMIN_SETUP_PASSWORD_HASH=$(php -r "echo password_hash('${IWB_POSTFIXADMIN_SETUP_PASSWORD}', PASSWORD_DEFAULT);")

sed -i "s|{{IWB_POSTFIXADMIN_SQL_USER}}|${IWB_POSTFIXADMIN_SQL_USER}|g" "$IWB_POSTFIXADMIN_CONFIG_OUT"
sed -i "s|{{IWB_POSTFIXADMIN_SQL_PASSWORD}}|${IWB_POSTFIXADMIN_SQL_PASSWORD}|g" "$IWB_POSTFIXADMIN_CONFIG_OUT"
sed -i "s|{{IWB_POSTFIXADMIN_SQL_DBNAME}}|${IWB_POSTFIXADMIN_SQL_DBNAME}|g" "$IWB_POSTFIXADMIN_CONFIG_OUT"
sed -i "s|{{IWB_POSTFIXADMIN_SETUP_PASSWORD_HASH}}|${IWB_POSTFIXADMIN_SETUP_PASSWORD_HASH}|g" "$IWB_POSTFIXADMIN_CONFIG_OUT"
sed -i "s|{{IWB_MAIL_USER}}|${IWB_MAIL_USER}|g" "$IWB_POSTFIXADMIN_CONFIG_OUT"
sed -i "s|{{IWB_DOMAIN}}|${IWB_DOMAIN}|g" "$IWB_POSTFIXADMIN_CONFIG_OUT"

chown nginx:nginx "$IWB_POSTFIXADMIN_CONFIG_OUT"
chmod 640 "$IWB_POSTFIXADMIN_CONFIG_OUT"
ln -sf "$IWB_POSTFIXADMIN_CONFIG_OUT" "$IWB_POSTFIXADMIN_SYMLINK"
chown nginx:nginx "$IWB_POSTFIXADMIN_SYMLINK"
chmod 640 "$IWB_POSTFIXADMIN_SYMLINK"

mkdir -p /var/www/html/postfixadmin/templates_c
chown -R nginx:nginx /var/www/html/postfixadmin/templates_c
chmod 755 /var/www/html/postfixadmin/templates_c

log "config.local.php created and linked."

# === Attempt cloud restore ===
RESTORED=false
log "Attempting PostfixAdmin database restore..."
if iwb-restore.sh postfix; then
  log "Restore succeeded."
  RESTORED=true
else
  log "No backup found. Proceeding with fresh PostfixAdmin setup..."

  log "Creating database '${IWB_POSTFIXADMIN_SQL_DBNAME}'..."
  mysql -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${IWB_POSTFIXADMIN_SQL_DBNAME}\`;
EOF
fi

# === Ensure DB user always exists
log "Ensuring database user '${IWB_POSTFIXADMIN_SQL_USER}' exists..."
mysql -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" <<EOF
CREATE USER IF NOT EXISTS '${IWB_POSTFIXADMIN_SQL_USER}'@'localhost' IDENTIFIED BY '${IWB_POSTFIXADMIN_SQL_PASSWORD}';
ALTER USER '${IWB_POSTFIXADMIN_SQL_USER}'@'localhost' IDENTIFIED BY '${IWB_POSTFIXADMIN_SQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${IWB_POSTFIXADMIN_SQL_DBNAME}\`.* TO '${IWB_POSTFIXADMIN_SQL_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

if [ "$RESTORED" = true ]; then
  touch "$IWB_POSTFIXADMIN_CONFIGURED_FLAG"
  touch "$IWB_POSTFIXADMIN_SCHEMA_FLAG"
  log "Skipping schema and admin user setup (restored from backup)."
else
  # === Run upgrade.php to initialize schema
  log "Initializing PostfixAdmin schema..."
  php --define register_argc_argv=on /var/www/html/postfixadmin/public/upgrade.php > /tmp/postfixadmin-upgrade.log

  touch "$IWB_POSTFIXADMIN_SCHEMA_FLAG"
  log "Schema initialized."

  # === Create admin user
  log "Creating PostfixAdmin superadmin account..."

  IWB_SUPERADMIN_EMAIL="${IWB_MAIL_USER}@${IWB_DOMAIN}"
  IWB_SUPERADMIN_PASS_HASH=$(php -r 'echo crypt("'"${IWB_MAIL_PASS}"'", "$1$" . bin2hex(random_bytes(4)));')

  mysql -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" "${IWB_POSTFIXADMIN_SQL_DBNAME}" <<EOF
INSERT INTO admin (username, password, superadmin, active, created)
VALUES ('$IWB_SUPERADMIN_EMAIL', '$IWB_SUPERADMIN_PASS_HASH', 1, 1, NOW())
ON DUPLICATE KEY UPDATE password = VALUES(password), active = 1, superadmin = 1;
EOF

  log "Superadmin account created: $IWB_SUPERADMIN_EMAIL"

  # === Add domain, mailbox, and catch-all alias
  log "Adding domain and primary mailbox to PostfixAdmin..."

  # Domain
  mysql -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" "${IWB_POSTFIXADMIN_SQL_DBNAME}" <<EOF
INSERT IGNORE INTO domain (domain, description, aliases, mailboxes, maxquota, active, created, modified)
VALUES ('${IWB_DOMAIN}', 'Primary mail domain', 100, 100, 0, 1, NOW(), NOW());
EOF

  # Mailbox
  IWB_FULL_EMAIL="${IWB_MAIL_USER}@${IWB_DOMAIN}"
  IWB_MAIL_PASS_HASH=$(php -r 'echo crypt("'"${IWB_MAIL_PASS}"'", "$1$" . bin2hex(random_bytes(4)));')

  mysql -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" "${IWB_POSTFIXADMIN_SQL_DBNAME}" <<EOF
INSERT INTO mailbox (username, password, name, maildir, quota, domain, local_part, active, created, modified)
VALUES ('$IWB_FULL_EMAIL', '$IWB_MAIL_PASS_HASH', '${IWB_MAIL_USER}', '${IWB_DOMAIN}/${IWB_MAIL_USER}/', 0, '${IWB_DOMAIN}', '${IWB_MAIL_USER}', 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE password = VALUES(password), active = 1;
EOF

mysql -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" "${IWB_POSTFIXADMIN_SQL_DBNAME}" <<EOF
INSERT IGNORE INTO domain_admins (username, domain)
VALUES ('${IWB_MAIL_USER}@${IWB_DOMAIN}', '${IWB_DOMAIN}');
EOF


  # Catch-all alias
  mysql -u root --socket=/run/mysqld/mysqld.sock -p"${IWB_MYSQL_ROOT_PASSWORD}" "${IWB_POSTFIXADMIN_SQL_DBNAME}" <<EOF
INSERT IGNORE INTO alias (address, goto, domain, created, modified, active)
VALUES ('@${IWB_DOMAIN}', '${IWB_FULL_EMAIL}', '${IWB_DOMAIN}', NOW(), NOW(), 1);
EOF

  log "Domain, mailbox, and catch-all alias setup complete."

  # === Backup DB now that it's initialized
  log "Backing up PostfixAdmin DB to storage provider..."
  iwb-backup.sh postfix snapshot || {
    log "$ERR_PREFIX PostfixAdmin DB backup failed."
    return 1
  }

  touch "$IWB_POSTFIXADMIN_CONFIGURED_FLAG"
fi

# ✅ Always disable setup.php
SETUP_PHP_PATH="/var/www/html/postfixadmin/public/setup.php"
if [ -f "$SETUP_PHP_PATH" ]; then
  mv "$SETUP_PHP_PATH" "${SETUP_PHP_PATH}.disabled"
  log "setup.php disabled."
fi

log "PostfixAdmin setup completed successfully."

(return 0 2>/dev/null) || exit 0
