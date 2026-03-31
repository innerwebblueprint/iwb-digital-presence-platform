#!/bin/bash
# includes/setup/scripts/storage-providers/r2/r2-setup.sh

CALL_MODULE=$MODULE
MODULE="$CALL_MODULE R2"
IWB_R2SETUP=false

if [ "${IWB_PERSISTENT_STORAGE}" = "r2" ]; then
  log "Initializing Cloudflare R2 backup system..."

  export IWB_R2_REGION="${IWB_R2_REGION:-auto}"
  export IWB_R2_ENDPOINT="https://${IWB_R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

  if AWS_ACCESS_KEY_ID="${IWB_R2_ACCESS_KEY_ID}" \
     AWS_SECRET_ACCESS_KEY="${IWB_R2_SECRET_ACCESS_KEY}" \
     AWS_DEFAULT_REGION="${IWB_R2_REGION}" \
     aws --endpoint-url "${IWB_R2_ENDPOINT}" s3 ls "s3://${IWB_R2_BUCKET}" >/dev/null 2>&1; then
    IWB_R2SETUP=true
    log "Cloudflare R2 access verified successfully for bucket: ${IWB_R2_BUCKET}"
  else
    log "$ERR_PREFIX Failed to verify Cloudflare R2 access. Check IWB_R2_* values."
    return 1
  fi
fi

MODULE=$CALL_MODULE
(return 0 2>/dev/null) || exit 0
