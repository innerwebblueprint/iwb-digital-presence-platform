#!/bin/bash
# includes/setup/scripts/storage-providers/storj/storj-setup.sh
#EXPORT IWB_STORJSETUP=false
CALL_MODULE=$MODULE
MODULE="$CALL_MODULE STORJ"
IWB_STORJSETUP=false

# Setup Storj Access
if [ "$IWB_PERSISTENT_STORAGE" == "storj" ]; then
  log "Initializing Storj backup system..."
  
  # Setup uplink config for root user
  mkdir -p /root/.config/storj/uplink
  cat > /root/.config/storj/uplink/config.ini <<EOF
[analytics]
enabled = false

[metrics]
addr =
EOF
  
  # Setup uplink config for n8n user
  mkdir -p /home/n8n/.config/storj/uplink
  cat > /home/n8n/.config/storj/uplink/config.ini <<EOF
[analytics]
enabled = false

[metrics]
addr =
EOF
  chown -R n8n:n8n /home/n8n/.config
  
  log "config.ini written to suppress analytics prompt for both root and n8n users"
  
  # Import access for root user
  if uplink access import default "$IWB_STORJ_GRANT" --force >/dev/null 2>&1; then
    uplink access use default >/dev/null 2>&1
    log "Storj access imported and set to default for root user"
  else
    log "$ERR_PREFIX Failed to import Storj access grant for root user"
    return 1
  fi
  
  # Import access for n8n user  
  if sudo -u n8n uplink access import default "$IWB_STORJ_GRANT" --force >/dev/null 2>&1; then
    sudo -u n8n uplink access use default >/dev/null 2>&1
    log "Storj access imported and set to default for n8n user"
  else
    log "$ERR_PREFIX Failed to import Storj access grant for n8n user"
    return 1
  fi
  log "Verifying Storj access for bucket: $IWB_STORJ_WPOPS_BUCKET"
  if ! uplink ls "sj://${IWB_STORJ_WPOPS_BUCKET}/" >/dev/null 2>&1; then
    log "$ERR_PREFIX Failed to verify Storj access for root user. Check IWB_STORJ_GRANT and IWB_STORJ_WPOPS_BUCKET values."
    return 1
  else
    log "Storj access verified successfully for root user for bucket: $IWB_STORJ_WPOPS_BUCKET"
  fi
  
  # Verify access for n8n user
  if ! sudo -u n8n uplink ls "sj://${IWB_STORJ_WPOPS_BUCKET}/" >/dev/null 2>&1; then
    log "$ERR_PREFIX Failed to verify Storj access for n8n user. Check IWB_STORJ_GRANT and IWB_STORJ_WPOPS_BUCKET values."
    return 1
  else
    IWB_STORJSETUP=true
    #EXPORT IWB_STORJSETUP=true
    log "Storj access verified successfully for both root and n8n users for bucket: $IWB_STORJ_WPOPS_BUCKET"
  fi
fi

MODULE=$CALL_MODULE