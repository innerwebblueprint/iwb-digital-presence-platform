#!/bin/bash
# includes/setup/scripts/akash-wallet-restore.sh
# Script to restore Akash wallet from Storj backup for deployments
# This script is designed to be called from n8n workflows

set -e

# Ensure non-interactive operation
export DEBIAN_FRONTEND=noninteractive
export AKASH_KEYRING_PASSPHRASE=""

MODULE="AKASH RESTORE"
source /var/setup/scripts/setup-env.sh
source /var/setup/scripts/storage-providers/storj/storj-functions.sh

# Akash wallet configuration
AKASH_WALLET_NAME="${COMPOSE_PROJECT_NAME}akashwallet"
AKASH_BACKUP_FILE="${COMPOSE_PROJECT_NAME}_akash-deploy-backup.json"
AKASH_BACKUP_PATH="/tmp/${AKASH_BACKUP_FILE}"
AKASH_STORJ_PATH="sj://${IWB_STORJ_WPOPS_BUCKET}/IWBDPP/akash/${AKASH_BACKUP_FILE}"
AKASH_KEYRING_BACKEND="test"

# Function to download wallet backup from Storj
download_wallet_backup() {
    log "Downloading wallet backup from Storj..."
    
    if storj_download "${AKASH_STORJ_PATH}" "${AKASH_BACKUP_PATH}"; then
        log "Successfully downloaded wallet backup from Storj"
        return 0
    else
        log "${ERR_PREFIX} Failed to download wallet backup from Storj"
        return 1
    fi
}

# Function to restore wallet from backup
restore_wallet_from_backup() {
    log "Restoring wallet from backup..."
    
    # Validate backup file exists and is readable
    if [ ! -f "${AKASH_BACKUP_PATH}" ] || [ ! -r "${AKASH_BACKUP_PATH}" ]; then
        log "${ERR_PREFIX} Backup file not found or not readable: ${AKASH_BACKUP_PATH}"
        return 1
    fi
    
    # Read mnemonic from backup file
    local mnemonic
    mnemonic=$(jq -r '.mnemonic' "${AKASH_BACKUP_PATH}" 2>/dev/null)
    
    if [ -z "$mnemonic" ] || [ "$mnemonic" = "null" ]; then
        log "${ERR_PREFIX} Failed to extract mnemonic from backup file"
        return 1
    fi
    
    # Validate mnemonic format (should be 24 words)
    local word_count
    word_count=$(echo "$mnemonic" | wc -w)
    if [ "$word_count" -ne 24 ]; then
        log "${ERR_PREFIX} Invalid mnemonic format: expected 24 words, got $word_count"
        return 1
    fi
    
    # Check if wallet already exists in keyring
    if provider-services keys show "${AKASH_WALLET_NAME}" \
        --keyring-backend "${AKASH_KEYRING_BACKEND}" >/dev/null 2>&1; then
        log "Wallet already exists in keyring. Skipping restoration."
        return 0
    fi
    
    # Restore wallet using mnemonic
    echo "$mnemonic" | provider-services keys add "${AKASH_WALLET_NAME}" \
        --recover \
        --keyring-backend "${AKASH_KEYRING_BACKEND}" \
        --interactive=false >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log "Successfully restored wallet: ${AKASH_WALLET_NAME}"
        return 0
    else
        log "${ERR_PREFIX} Failed to restore wallet from mnemonic"
        return 1
    fi
}

# Function to get wallet address
get_wallet_address() {
    local address
    address=$(provider-services keys show "${AKASH_WALLET_NAME}" \
        --keyring-backend "${AKASH_KEYRING_BACKEND}" \
        --address 2>/dev/null)
    
    if [ -z "$address" ]; then
        log "${ERR_PREFIX} Failed to get wallet address"
        return 1
    fi
    
    echo "$address"
    return 0
}

# Function to clean up restored wallet (for security)
cleanup_wallet() {
    log "Cleaning up restored wallet for security..."
    
    if echo "" | provider-services keys delete "${AKASH_WALLET_NAME}" \
        --keyring-backend "${AKASH_KEYRING_BACKEND}" \
        --yes \
        --force >/dev/null 2>&1; then
        log "Successfully cleaned up wallet from keyring"
    else
        log "WARNING: Failed to clean up wallet from keyring"
    fi
    
    # Clean up backup file
    rm -f "${AKASH_BACKUP_PATH}"
}

# Function to get wallet info for n8n (NO SENSITIVE DATA)
get_wallet_info() {
    local address
    address=$(get_wallet_address)
    
    if [ $? -ne 0 ]; then
        echo '{"error": "Failed to get wallet address"}'
        return 1
    fi
    
    # Read additional info from backup (excluding sensitive data)
    local wallet_name created_at
    wallet_name=$(jq -r '.walletName' "${AKASH_BACKUP_PATH}")
    created_at=$(jq -r '.createdAt' "${AKASH_BACKUP_PATH}")
    
    # Output JSON for n8n consumption (NO MNEMONIC OR SENSITIVE DATA)
    jq -n \
        --arg wallet_name "$wallet_name" \
        --arg address "$address" \
        --arg created_at "$created_at" \
        --arg keyring_backend "$AKASH_KEYRING_BACKEND" \
        '{
            "wallet_name": $wallet_name,
            "address": $address,
            "created_at": $created_at,
            "keyring_backend": $keyring_backend,
            "status": "ready_for_deployment"
        }'
}

# Main restore function
restore_akash_wallet() {
    log "Starting Akash wallet restoration..."
    
    # Download backup from Storj
    if ! download_wallet_backup; then
        echo '{"error": "Failed to download wallet backup", "status": "failed"}'
        return 1
    fi
    
    # Restore wallet from backup
    if ! restore_wallet_from_backup; then
        echo '{"error": "Failed to restore wallet from backup", "status": "failed"}'
        rm -f "${AKASH_BACKUP_PATH}"
        return 1
    fi
    
    # Get wallet info for output (NO SENSITIVE DATA)
    get_wallet_info
    local result=$?
    
    # Clean up backup file (keep wallet in keyring for deployment use)
    rm -f "${AKASH_BACKUP_PATH}"
    
    return $result
}

# Function specifically for cleanup (to be called after deployment)
cleanup_after_deployment() {
    log "Cleaning up after deployment..."
    cleanup_wallet
    echo '{"status": "cleaned_up", "message": "Wallet removed from keyring for security"}'
}

# Main script logic
case "${1:-restore}" in
    "restore")
        restore_akash_wallet
        ;;
    "cleanup")
        cleanup_after_deployment
        ;;
    "info")
        if [ -f "${AKASH_BACKUP_PATH}" ]; then
            get_wallet_info
        else
            restore_akash_wallet
        fi
        ;;
    *)
        echo '{"error": "Invalid action. Use: restore, cleanup, or info", "status": "failed"}'
        exit 1
        ;;
esac
