#!/bin/sh

set -eu

REAL_AWS_BIN="/usr/bin/aws"

if [ ! -x "$REAL_AWS_BIN" ]; then
  echo "ERROR: aws CLI binary not found at $REAL_AWS_BIN" >&2
  exit 1
fi

if [ -n "${IWB_R2_ACCESS_KEY_ID:-}" ] && [ -n "${IWB_R2_SECRET_ACCESS_KEY:-}" ]; then
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$IWB_R2_ACCESS_KEY_ID}"
  export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$IWB_R2_SECRET_ACCESS_KEY}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${IWB_R2_REGION:-auto}}"
fi

if [ -n "${IWB_R2_ACCOUNT_ID:-}" ]; then
  endpoint_url="https://${IWB_R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
  endpoint_arg_present="false"

  for arg in "$@"; do
    if [ "$arg" = "--endpoint-url" ]; then
      endpoint_arg_present="true"
      break
    fi
  done

  if [ "$endpoint_arg_present" != "true" ]; then
    set -- --endpoint-url "$endpoint_url" "$@"
  fi
fi

exec "$REAL_AWS_BIN" "$@"
