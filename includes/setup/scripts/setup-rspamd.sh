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

# Process actions.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/actions.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering actions.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/actions.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/actions.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/actions.conf" "/etc/rspamd/local.d/actions.conf"
fi

# Process milter_headers.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/milter_headers.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering milter_headers.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/milter_headers.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/milter_headers.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/milter_headers.conf" "/etc/rspamd/local.d/milter_headers.conf"
fi

# Process settings.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/settings.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering settings.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      -e "s|{{IWB_MAIL_USER}}|$IWB_MAIL_USER|g" \
      "$IWB_CONFIGDIR/mail/rspamd/settings.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/settings.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/settings.conf" "/etc/rspamd/local.d/settings.conf"
fi

# Process rbl.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/rbl.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering rbl.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/rbl.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/rbl.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/rbl.conf" "/etc/rspamd/local.d/rbl.conf"
fi

# Process redis.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/redis.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering redis.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/redis.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/redis.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/redis.conf" "/etc/rspamd/local.d/redis.conf"
fi

# Process greylist.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/greylist.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering greylist.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/greylist.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/greylist.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/greylist.conf" "/etc/rspamd/local.d/greylist.conf"
fi

# Process classifier-bayes.conf.template
if [ -f "$IWB_CONFIGDIR/mail/rspamd/classifier-bayes.conf.template" ]; then
  echo -e "$IWB_PREFIX Rendering classifier-bayes.conf.template..."
  sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
      "$IWB_CONFIGDIR/mail/rspamd/classifier-bayes.conf.template" > "$IWB_CONFIGDIR/mail/rspamd/classifier-bayes.conf"
  ln -sf "$IWB_CONFIGDIR/mail/rspamd/classifier-bayes.conf" "/etc/rspamd/local.d/classifier-bayes.conf"
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
