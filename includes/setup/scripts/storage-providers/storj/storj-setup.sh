#!/bin/bash
# includes/setup/scripts/storage-providers/storj/storj-setup.sh
#EXPORT IWB_STORJSETUP=false
CALL_MODULE=$MODULE
MODULE="$CALL_MODULE STORJ"
IWB_STORJSETUP=false

# Setup Storj Access
if [ "$IWB_PERSISTENT_STORAGE" == "storj" ]; then
  log "Initializing Storj backup system..."
  mkdir -p /root/.config/storj/uplink
  cat > /root/.config/storj/uplink/config.ini <<EOF
[analytics]
enabled = false

[metrics]
addr =
EOF
  log "config.ini written to suppress analytics prompt"
  if uplink access import default "$IWB_STORJ_GRANT" --force >/dev/null 2>&1; then
    uplink access use default >/dev/null 2>&1
    log "Storj access imported and set to default"
  else
    log "$ERR_PREFIX Failed to import Storj access grant"
    return 1
  fi
  log "Verifying Storj access for bucket: $IWB_STORJ_WPOPS_BUCKET"
  if ! uplink ls "sj://${IWB_STORJ_WPOPS_BUCKET}/" >/dev/null 2>&1; then
    log "$ERR_PREFIX Failed to verify Storj access. Check IWB_STORJ_GRANT and IWB_STORJ_WPOPS_BUCKET values."
    return 1
  else
    IWB_STORJSETUP=true
    #EXPORT IWB_STORJSETUP=true
    log "Storj access verified successfully for bucket: $IWB_STORJ_WPOPS_BUCKET"
  fi
fi

MODULE=$CALL_MODULE