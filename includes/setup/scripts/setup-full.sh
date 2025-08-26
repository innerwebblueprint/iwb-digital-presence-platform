#!/bin/bash
# includes/setup/scripts/setup-full.sh

MODULE="FULL"

# Setup and verify storage provider Credentials
log "Setup and verify storage provider Credentials..."
if ! source /var/setup/scripts/storage-providers/storage-router.sh; then
  log "$ERR_PREFIX Storage Provider Setup failed... Aborting container startup."
  exit 1
fi

# Setup Database Enviornment
log "Setup and verify Database Enviornment"
if ! source /var/setup/scripts/db-setup.sh; then
  log "$ERR_PREFIX Databse Enviornment Setup failed... Aborting container startup."
  return 1
fi

# Setup PostfixAdmin (restore, config, schema, backup)
if ! source /var/setup/scripts/postfixadmin-setup.sh; then
  log "$ERR_PREFIX PostfixAdmin setup failed. Aborting."
  return 1
fi

# Setup Pre Web Server Enviornment for getting certs
if ! source /var/setup/scripts/setup-pre-webserver.sh; then
  log "$ERR_PREFIX Seting up Web Server Enviorment failed. Aborting."
  return 1
fi

# Handle SSL certificate setup via Let's Encrypt
log "Preparing certificate setup for $IWB_DOMAIN..."
if ! source /var/setup/scripts/setup-sslcerts.sh; then
  log $MODULE "$ERR_PREFIX Certificate setup failed. Aborting container startup."
  exit 1
fi

# Setup Nginx virtual host templates for SSL (we exit if we fail to get certs so this is safe)
log "Processing and linking SSL-enabled Nginx configs..."

SSL_TEMPLATE_DIR="$IWB_CONFIGDIR/http/nginx/sites-available"
NGINX_CONF_DIR="/etc/nginx/http.d"

# Let's empty that directory to make sure nothing is in there from before
rm -rf "$NGINX_CONF_DIR" 
mkdir -p "$NGINX_CONF_DIR"

for TEMPLATE in "$SSL_TEMPLATE_DIR"/*ssl*.conf.template; do
  if [ -f "$TEMPLATE" ]; then
    BASENAME=$(basename "$TEMPLATE" .template)   # e.g. default-ssl.conf
    OUTPUT="$SSL_TEMPLATE_DIR/$BASENAME"
    LINK_TARGET="$NGINX_CONF_DIR/$BASENAME"

    sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
    -e "s|{{COMPOSE_PROJECT_NAME}}|$COMPOSE_PROJECT_NAME|g" \
    -e "s|{{IWB_STORJ_MEDIA_KEY}}|$IWB_STORJ_MEDIA_KEY|g" \
    -e "s|{{IWB_STORJ_MEDIA_BUCKET}}|$IWB_STORJ_MEDIA_BUCKET|g" \
    "$TEMPLATE" > "$OUTPUT"

    ln -sf "$OUTPUT" "$LINK_TARGET"

    log "Linked SSL config: $BASENAME"
  else
    log "$ERR_PREFIX No matching SSL templates found in $SSL_TEMPLATE_DIR"
  fi
done

# Setting up eMail
log "Setting up eMail"

log "Creating Postfix configs"
sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
    -e "s|{{PUBLIC_IP}}|$PUBLIC_IP|g" \
    "$IWB_CONFIGDIR/mail/postfix/postfix-main-full.cf.template" \
    > "$IWB_CONFIGDIR/mail/postfix/postfix-main-full.cf"


sed "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
    "$IWB_CONFIGDIR/mail/dovecot/dovecot-99-full.conf.template" > "$IWB_CONFIGDIR/mail/dovecot/dovecot-99-full.conf"


# Render Postfix SQL maps
log "Rendering Postfix SQL config maps..."

mkdir -p /etc/postfix/sql
rm -f /etc/dovecot/conf.d/10-auth.conf


# Alias map
sed -e "s|{{IWB_POSTFIXADMIN_SQL_USER}}|$IWB_POSTFIXADMIN_SQL_USER|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_PASSWORD}}|$IWB_POSTFIXADMIN_SQL_PASSWORD|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_DBNAME}}|$IWB_POSTFIXADMIN_SQL_DBNAME|g" \
    "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_alias_maps.template.cf" \
    > "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_alias_maps.cf"
ln -sf "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_alias_maps.cf" /etc/postfix/sql/mysql_virtual_alias_maps.cf

# Mailbox map
sed -e "s|{{IWB_POSTFIXADMIN_SQL_USER}}|$IWB_POSTFIXADMIN_SQL_USER|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_PASSWORD}}|$IWB_POSTFIXADMIN_SQL_PASSWORD|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_DBNAME}}|$IWB_POSTFIXADMIN_SQL_DBNAME|g" \
    "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_mailbox_maps.template.cf" \
    > "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_mailbox_maps.cf"
ln -sf "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_mailbox_maps.cf" /etc/postfix/sql/mysql_virtual_mailbox_maps.cf

# Domain map
sed -e "s|{{IWB_POSTFIXADMIN_SQL_USER}}|$IWB_POSTFIXADMIN_SQL_USER|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_PASSWORD}}|$IWB_POSTFIXADMIN_SQL_PASSWORD|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_DBNAME}}|$IWB_POSTFIXADMIN_SQL_DBNAME|g" \
    "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_domains_maps.template.cf" \
    > "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_domains_maps.cf"
ln -sf "$IWB_CONFIGDIR/mail/postfix/sql/mysql_virtual_domains_maps.cf" /etc/postfix/sql/mysql_virtual_domains_maps.cf


log "Rendering Dovecot SQL config"
sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_USER}}|$IWB_POSTFIXADMIN_SQL_USER|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_PASSWORD}}|$IWB_POSTFIXADMIN_SQL_PASSWORD|g" \
    -e "s|{{IWB_POSTFIXADMIN_SQL_DBNAME}}|$IWB_POSTFIXADMIN_SQL_DBNAME|g" \
    "$IWB_CONFIGDIR/mail/dovecot/dovecot-sql.conf.template" > /etc/dovecot/dovecot-sql.conf.ext


# Symlink configuration files
log "Linking config files"
mkdir -p /etc/rsyslog.d
mkdir -p /etc/supervisor/conf.d
ln -sf $IWB_CONFIGDIR/mail/postfix/postfix-main-full.cf /etc/postfix/main.cf
ln -sf $IWB_CONFIGDIR/mail/postfix/postfix-master-full.cf /etc/postfix/master.cf
ln -sf $IWB_CONFIGDIR/mail/dovecot/dovecot-99-full.conf /etc/dovecot/conf.d/99-local.conf
ln -sf $IWB_CONFIGDIR/system/rsyslogd/rsyslogd-10-postfix.conf /etc/rsyslog.d/10-postfix.conf
ln -sf $IWB_CONFIGDIR/system/supervisord/supervisord-full.conf /etc/supervisor/conf.d/supervisord.conf

# Restore Usser Mail if Archived
log "Attempting to restore user mailboxes for $IWB_DOMAIN..."
if ! iwb-restore.sh mail latest; then
  log "$ERR_PREFIX No user mailboxes found... this is normal on a first run"
fi
 
# Setup RSPAMD
log "Preparing rspamd setup for $IWB_DOMAIN..."
if ! source /var/setup/scripts/setup-rspamd.sh; then
  log "$ERR_PREFIX Rspamd setup failed. Aborting container startup."
  (return 0 2>/dev/null) || exit 0
fi

# Setup Wordpress
log "Setting up Wordpress for: www.$IWB_DOMAIN..."
if ! source /var/setup/scripts/setup-wordpress.sh; then
  log $MODULE "$ERR_PREFIX Setting up wordpress failed, aborting container startup."
  (return 0 2>/dev/null) || exit 0
fi

# Setup N8N
log "Setting up n8n at: n8n.$IWB_DOMAIN..."
if ! source /var/setup/scripts/setup-n8n.sh; then
  log $MODULE "$ERR_PREFIX Setting up n8n failed, aborting container startup."
  (return 0 2>/dev/null) || exit 0
fi

# === Stop manually started MariaDB if needed ===
if [ -f "$IWB_MARIADB_PID_FILE" ]; then
  PID=$(cat "$IWB_MARIADB_PID_FILE")
  echo "$IWB_PREFIX Shutting down temporary MariaDB (PID $PID)..."
  
  #kill "$PID"
  mariadb-admin -u root -p"$IWB_MYSQL_ROOT_PASSWORD" shutdown
  
  for i in {1..10}; do
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "$IWB_PREFIX MariaDB has shut down cleanly."
      break
    fi
    sleep 1
    if [ "$i" -eq 10 ]; then
      echo "$IWB_PREFIX $ERR_PREFIX MariaDB did not shut down in time — force killing."
      kill -9 "$PID"
    fi
  done

  rm -f "$IWB_MARIADB_PID_FILE"
fi

# Safe exit/return mechanism
(return 0 2>/dev/null) || exit 0

