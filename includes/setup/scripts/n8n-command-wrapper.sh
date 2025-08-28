#!/bin/bash

# n8n Command Wrapper Script
# This script provides a safe interface for n8n to execute specific commands
# with proper argument validation and logging
# SECURITY: Runs with clean environment to prevent access to sensitive variables

set -euo pipefail

# Define allowed commands and their paths
UPLINK_CMD="/usr/local/bin/uplink"
PROVIDER_SERVICES_CMD="/usr/local/bin/provider-services"
AKASH_WALLET_CMD="/var/setup/scripts/akash-wallet-restore.sh"

# Load only the specific environment variables n8n needs
# This prevents n8n from accessing sensitive variables
if [ -f /var/setup/.env ]; then
    # Extract only the bucket name, nothing else
    export IWB_STORJ_WPOPS_BUCKET=$(grep "^IWB_STORJ_WPOPS_BUCKET=" /var/setup/.env 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] n8n-wrapper: $*" | tee -a /var/log/n8n-commands.log
}

# Input validation function
validate_args() {
    local cmd="$1"
    shift
    local args=("$@")
    
    # Basic validation to prevent command injection
    for arg in "${args[@]}"; do
        case "$arg" in
            *";"*|*"&"*|*"|"*|*">"*|*"<"*|*'$'*|*'`'*)
                log "SECURITY: Rejected potentially dangerous argument: $arg"
                return 1
                ;;
        esac
    done
    
    case "$cmd" in
        "uplink")
            # Add specific uplink argument validation here if needed
            log "Executing uplink with args: ${args[*]}"
            return 0
            ;;
        "provider-services")
            # Add specific provider-services argument validation here if needed
            log "Executing provider-services with args: ${args[*]}"
            return 0
            ;;
        "akash-wallet")
            # Validate akash-wallet arguments (restore, cleanup, info)
            if [ ${#args[@]} -eq 0 ] || [[ "${args[0]}" =~ ^(restore|cleanup|info)$ ]]; then
                log "Executing akash-wallet with args: ${args[*]}"
                return 0
            else
                log "SECURITY: Invalid akash-wallet action: ${args[0]}"
                return 1
            fi
            ;;
        *)
            log "SECURITY: Unknown command requested: $cmd"
            return 1
            ;;
    esac
}

# Main execution function
execute_command() {
    local cmd="$1"
    shift
    local args=("$@")
    
    case "$cmd" in
        "uplink")
            if [[ -x "$UPLINK_CMD" ]]; then
                # Run uplink with clean environment, only essential variables
                env -i \
                    HOME="/home/n8n" \
                    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
                    IWB_STORJ_WPOPS_BUCKET="$IWB_STORJ_WPOPS_BUCKET" \
                    "$UPLINK_CMD" "${args[@]}"
            else
                log "ERROR: uplink command not found or not executable"
                exit 1
            fi
            ;;
        "provider-services")
            if [[ -x "$PROVIDER_SERVICES_CMD" ]]; then
                # Run provider-services as root with minimal environment and non-interactive
                echo "" | sudo env -i \
                    HOME="/root" \
                    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
                    DEBIAN_FRONTEND=noninteractive \
                    AKASH_KEYRING_PASSPHRASE="" \
                    "$PROVIDER_SERVICES_CMD" "${args[@]}"
            else
                log "ERROR: provider-services command not found or not executable"
                exit 1
            fi
            ;;
        "akash-wallet")
            if [[ -x "$AKASH_WALLET_CMD" ]]; then
                # Run akash-wallet script with full environment access (needed for Storj operations)
                "$AKASH_WALLET_CMD" "${args[@]}"
            else
                log "ERROR: akash-wallet command not found or not executable"
                exit 1
            fi
            ;;
        *)
            log "ERROR: Invalid command: $cmd"
            exit 1
            ;;
    esac
}

# Main script logic
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <command> [args...]"
    echo "Allowed commands: uplink, provider-services, akash-wallet"
    exit 1
fi

COMMAND="$1"
shift
ARGS=("$@")

log "Command request: $COMMAND with args: ${ARGS[*]}"

# Validate and execute
if validate_args "$COMMAND" "${ARGS[@]}"; then
    execute_command "$COMMAND" "${ARGS[@]}"
    log "Command completed successfully: $COMMAND"
else
    log "Command validation failed: $COMMAND"
    exit 1
fi
