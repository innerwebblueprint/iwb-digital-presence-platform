#!/bin/bash
# includes/setup/scripts/storage-providers/storj/storj-setup.sh
#EXPORT IWB_STORJSETUP=false
CALL_MODULE=$MODULE
MODULE="$CALL_MODULE STORJ"
export IWB_STORJSETUP="${IWB_STORJSETUP:-false}"

has_real_storj_grant() {
  local raw_grant="${IWB_STORJ_GRANT:-}"
  local trimmed_grant
  trimmed_grant=$(printf '%s' "$raw_grant" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  [ -n "$trimmed_grant" ] && [ "${trimmed_grant#\#}" = "$trimmed_grant" ]
}

setup_uplink_config() {
  local user_home="$1"
  local owner="$2"

  mkdir -p "${user_home}/.config/storj/uplink"
  cat > "${user_home}/.config/storj/uplink/config.ini" <<EOF
[analytics]
enabled = false

[metrics]
addr =
EOF

  if [ -n "$owner" ]; then
    chown -R "$owner" "${user_home}/.config"
  fi
}

setup_storj_access() {
  if ! has_real_storj_grant; then
    if [ "$IWB_PERSISTENT_STORAGE" = "storj" ]; then
      log "$ERR_PREFIX Storj storage is selected, but IWB_STORJ_GRANT is missing or still set to a placeholder value."
      return 1
    fi

    log "No valid Storj access grant provided. Skipping Storj access setup."
    return 0
  fi

  log "Initializing Storj access..."

  setup_uplink_config "/root" ""
  setup_uplink_config "/home/n8n" "n8n:n8n"

  log "config.ini written to suppress analytics prompt for both root and n8n users"

  if uplink access import default "$IWB_STORJ_GRANT" --force >/dev/null 2>&1; then
    uplink access use default >/dev/null 2>&1
    log "Storj access imported and set to default for root user"
  else
    log "$ERR_PREFIX Failed to import Storj access grant for root user"
    return 1
  fi

  if sudo -u n8n uplink access import default "$IWB_STORJ_GRANT" --force >/dev/null 2>&1; then
    sudo -u n8n uplink access use default >/dev/null 2>&1
    log "Storj access imported and set to default for n8n user"
  else
    log "$ERR_PREFIX Failed to import Storj access grant for n8n user"
    return 1
  fi

  export IWB_STORJSETUP=true

  if [ -z "${IWB_STORJ_WPOPS_BUCKET:-}" ]; then
    log "Storj access imported for root and n8n users. Bucket verification skipped because IWB_STORJ_WPOPS_BUCKET is not set."
  else
    log "Verifying Storj access for bucket: $IWB_STORJ_WPOPS_BUCKET"
    if ! uplink ls "sj://${IWB_STORJ_WPOPS_BUCKET}/" >/dev/null 2>&1; then
      log "$ERR_PREFIX Failed to verify Storj access for root user. Check IWB_STORJ_GRANT and IWB_STORJ_WPOPS_BUCKET values."
      return 1
    fi

    if ! sudo -u n8n uplink ls "sj://${IWB_STORJ_WPOPS_BUCKET}/" >/dev/null 2>&1; then
      log "$ERR_PREFIX Failed to verify Storj access for n8n user. Check IWB_STORJ_GRANT and IWB_STORJ_WPOPS_BUCKET values."
      return 1
    fi

    log "Storj access verified successfully for both root and n8n users for bucket: $IWB_STORJ_WPOPS_BUCKET"
  fi
}

# Setup Storj Access
if [ "$IWB_PERSISTENT_STORAGE" == "storj" ] || has_real_storj_grant; then
  if ! setup_storj_access; then
    return 1
  fi
fi

MODULE=$CALL_MODULE
(return 0 2>/dev/null) || exit 0
