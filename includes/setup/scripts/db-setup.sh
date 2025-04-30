#!/bin/bash
# includes/setup/scripts/db-setup.sh

set -e

MODULE="DB"

log "Starting MariaDB setup..."

# === Path structure for persistent state ===
IWB_DATA_ROOT="/var/data"
IWB_STATE_DIR="${IWB_DATA_ROOT}/state"
IWB_DB_INIT_FLAG="${IWB_STATE_DIR}/db_initialized"

# Ensure necessary directories
mkdir -p /run/mysqld /var/lib/mysql "$IWB_STATE_DIR"
chown -R mysql:mysql /run/mysqld
chown -R mysql:mysql /var/lib/mysql

log "Linking custom MariaDB override config..."
mkdir -p /etc/my.cnf.d
ln -sf "$IWB_CONFIGDIR/mariadb/iwb_mariadb-server.cnf" /etc/my.cnf.d/iwb_mariadb-server.cnf

# Remove skip networking from default mariadb-server.cnf
sed -i '/skip-networking/d' /etc/my.cnf.d/mariadb-server.cnf

# Initialize MariaDB if it's missing
if [ ! -d /var/lib/mysql/mysql ]; then
  log "Detected uninitialized MariaDB directory. Bootstrapping..."
  mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql > /dev/null 2>&1
fi

# Start MariaDB manually for setup
log "Starting MariaDB manually..."
mariadbd-safe --datadir=/var/lib/mysql > /tmp/mariadb.log 2>&1 &
SAFE_WRAPPER_PID=$!

# Wait for MariaDB to become available
MAX_TRIES=20
TRIES=0
until mysqladmin ping --silent --socket=/run/mysqld/mysqld.sock; do
  if [ "$TRIES" -ge "$MAX_TRIES" ]; then
    echo "${IWB_PREFIX} ${ERR_PREFIX} MariaDB did not start after $MAX_TRIES attempts. Aborting setup."
    tail -n 50 /tmp/mariadb.log
    return 1
  fi
  log "Waiting for MariaDB to become available... ($TRIES)"
  TRIES=$((TRIES+1))
  sleep 1
done

# Find actual mariadbd PID (not the safe wrapper)
IWB_PID=$(ps -eo pid,ppid,comm,args | awk -v ppid="$SAFE_WRAPPER_PID" '$2 == ppid && $3 == "mariadbd" { print $1 }' | head -n 1)

if [ -n "$IWB_PID" ]; then
  echo "$IWB_PID" > "$IWB_MARIADB_PID_FILE"
  log "Captured MariaDB PID: $IWB_PID"
else
  log "$ERR_PREFIX Failed to capture MariaDB PID from wrapper ($SAFE_WRAPPER_PID)"
  return 1
fi

log "MariaDB is up and running. Continuing with setup."

# Set root password if first-time
if [ ! -f "$IWB_DB_INIT_FLAG" ]; then
  log "Setting root password..."
  mysql -u root --socket=/run/mysqld/mysqld.sock -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${IWB_MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"
  touch "$IWB_DB_INIT_FLAG"
fi

log "MariaDB setup complete."
return 0
