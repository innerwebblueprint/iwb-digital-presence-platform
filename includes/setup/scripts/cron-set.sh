

echo "$IWB_PREFIX Setting up hourly cron for DB and mail backup..."

cat <<EOF > /etc/cron.hourly/backup_postfixadmin.sh
#!/bin/sh
mysqldump -u root -p"${IWB_MYSQL_ROOT_PASSWORD}" postfixadmin > "$SQL_BACKUP_PATH"
uplink cp "$SQL_BACKUP_PATH" "$STORJ_DB_KEY"
tar -czf "$MAIL_BACKUP_PATH" /data/mail
uplink cp "$MAIL_BACKUP_PATH" "$STORJ_MAIL_KEY"
EOF

chmod +x /etc/cron.hourly/backup_postfixadmin.sh
