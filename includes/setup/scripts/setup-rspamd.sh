#!/bin/bash
# includes/setup/scripts/setup-rspamd.sh



# Process rspamd.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/rspamd.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering rspamd.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/rspamd.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/rspamd.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/rspamd.conf" "/etc/rspamd/override.d/rspamd.conf"
fi

# Process modules.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/modules.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering modules.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/modules.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/modules.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/modules.conf" "/etc/rspamd/modules.conf"
fi

# Process dkim_signing.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/dkim_signing.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering dkim_signing.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/dkim_signing.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/dkim_signing.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/dkim_signing.conf" "/etc/rspamd/local.d/dkim_signing.conf"
fi

# Process logging.inc.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/logging.inc.template" ]; then
  echo -e "$IWB_PREFIX Rendering logging.inc.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/logging.inc.template" > "$IWB_CONFIGDIR/mail/rspamd/logging.inc"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/logging.inc" "/etc/rspamd/local.d/logging.inc"
fi

# Process worker-controller.inc.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/worker-controller.inc.template" ]; then
  echo -e "$IWB_PREFIX Rendering worker-controller.inc.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      -e "s|{{IWB_RSPAMD_CONTROLLER_PASSWORD}}|$IWB_RSPAMD_CONTROLLER_PASSWORD|g" \
      -e "s|{{IWB_RSPAMD_CONTROLLER_ENABLE_PASSWORD}}|$IWB_RSPAMD_CONTROLLER_ENABLE_PASSWORD|g" \
      "$IWB_CONFIGDIR/mail/rspamd/worker-controller.inc.template" > "$IWB_CONFIGDIR/mail/rspamd/worker-controller.inc"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/worker-controller.inc" "/etc/rspamd/local.d/worker-controller.inc"
fi

# Process worker-proxy.inc.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/worker-proxy.inc.template" ]; then
  echo -e "$IWB_PREFIX Rendering worker-proxy.inc.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/worker-proxy.inc.template" > "$IWB_CONFIGDIR/mail/rspamd/worker-proxy.inc"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/worker-proxy.inc" "/etc/rspamd/local.d/worker-proxy.inc"
fi

# Process redis.conf.template
if [ -f "$IWB_CONFIGDIR/system/redis/redis.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering redis.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/system/redis/redis.conf.template" > "$IWB_CONFIGDIR//system/redis/redis.conf"
  mkdir -p /etc/redis/
  ln -sf "$IWB_CONFIGDIR/system/redis/redis.conf" "/etc/redis/redis.conf"
fi

return 0