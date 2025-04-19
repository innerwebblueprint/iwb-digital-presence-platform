#!/bin/bash
# includes/setup/scripts/storage-providers/storj/storj-setup.sh
#EXPORT IWB_STORJSETUP=false
IWB_STORJSETUP=false
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
    return 1
  fi
  echo -e "$IWB_PREFIX Verifying Storj access for bucket: $STORJ_WPOPS_BUCKET"
  if ! uplink ls "sj://${STORJ_WPOPS_BUCKET}/"; then
    echo -e "$IWB_PREFIX $ERR_PREFIX Failed to verify Storj access. Check STORJ_GRANT and STORJ_WPOPS_BUCKET values."
    return 1
  else
    IWB_STORJSETUP=true
    #EXPORT IWB_STORJSETUP=true
    echo -e "$IWB_PREFIX Storj access verified successfully for bucket: $STORJ_WPOPS_BUCKET"
  fi
fi