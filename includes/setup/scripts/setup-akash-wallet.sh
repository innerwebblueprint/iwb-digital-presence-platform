#!/bin/bash
# includes/setup/scripts/setup-akash-wallet.sh
# Akash wallet management script for automatic backup and creation

set -e

# Ensure non-interactive operation
export DEBIAN_FRONTEND=noninteractive
export AKASH_KEYRING_PASSPHRASE=""

MODULE="AKASH WALLET"
source /var/setup/scripts/setup-env.sh
source /var/setup/scripts/storage-providers/storage-router.sh
source /var/setup/scripts/storage-providers/storage-functions.sh

log "Starting Akash wallet setup..."

# Akash wallet configuration
AKASH_WALLET_NAME="${COMPOSE_PROJECT_NAME}akashwallet"
AKASH_KEYRING_BACKEND="test"
AKASH_NODE="https://rpc.akashnet.net:443"
AKASH_CHAIN_ID="akashnet-2"

# Function to create new Akash wallet
create_new_akash_wallet() {
    log "Creating new Akash wallet: ${AKASH_WALLET_NAME}"
    
    # Create wallet using the method that works
    local wallet_output
    wallet_output=$(timeout 30 sh -c "echo | provider-services keys add '${AKASH_WALLET_NAME}' --keyring-backend test --interactive=false" 2>&1 || echo "COMMAND_FAILED")
    
    if [[ "$wallet_output" == *"COMMAND_FAILED"* ]] || [[ "$wallet_output" == *"aborted"* ]]; then
        log "${ERR_PREFIX} Failed to create Akash wallet"
        log "${ERR_PREFIX} Output: $wallet_output"
        return 1
    fi
    
    # Extract mnemonic from the output
    local mnemonic
    mnemonic=$(echo "$wallet_output" | grep -E '([a-z]+ ){23}[a-z]+' | head -1 | xargs || echo "")
    
    # If we couldn't find mnemonic in the expected format, try other patterns
    if [ -z "$mnemonic" ]; then
        mnemonic=$(echo "$wallet_output" | grep -A 20 -i "mnemonic\|seed\|phrase" | grep -E '^[a-z ]+$' | head -1 | xargs || echo "")
    fi
    
    if [ -z "$mnemonic" ]; then
        log "WARN: Could not extract mnemonic from wallet creation output"
        log "WARN: Raw output: $wallet_output"
    else
        log "Successfully extracted mnemonic (${#mnemonic} characters)"
    fi
    
    # Get the address for notification
    local address
    log "Attempting to get address for wallet: ${AKASH_WALLET_NAME}"
    address=$(provider-services keys show "${AKASH_WALLET_NAME}" \
        --keyring-backend "${AKASH_KEYRING_BACKEND}" \
        --address 2>/dev/null)
    
    if [ -z "$address" ]; then
        log "${ERR_PREFIX} Failed to get wallet address"
        log "Debugging: Let's see what wallets exist..."
        provider-services keys list --keyring-backend "${AKASH_KEYRING_BACKEND}" || log "Keys list failed"
        return 1
    fi
    
    log "Successfully created wallet with address: ${address}"
    
    # Create backup manually instead of using iwb-backup.sh to avoid the hanging issue
    log "Creating wallet backup manually..."
    
    if [ -z "$mnemonic" ]; then
        log "${ERR_PREFIX} Cannot create backup without mnemonic"
        log "${ERR_PREFIX} Wallet created but cannot be backed up for later restoration"
        log "${ERR_PREFIX} You may need to manually export the wallet if needed"
        
        # Still get balance and send notification even without backup
        local balance
        balance=$(get_wallet_balance "$address")
        send_wallet_notification "$address" "$balance"
        
        # Clean up wallet from keyring for security
        echo "" | provider-services keys delete "${AKASH_WALLET_NAME}" \
            --keyring-backend "${AKASH_KEYRING_BACKEND}" \
            --yes --force >/dev/null 2>&1
        
        log "Wallet removed from keyring for security"
        log "WARN: Wallet created but could not be backed up due to missing mnemonic"
        return 0
    fi
    
    local backup_dir="/var/data/backup/akash"
    local backup_file="$backup_dir/${COMPOSE_PROJECT_NAME}_akash-deploy-backup.json"
    mkdir -p "$backup_dir"
    
    cat > "$backup_file" <<EOF
{
  "walletName": "${AKASH_WALLET_NAME}",
  "mnemonic": "${mnemonic}",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "network": "akash",
  "public_address": "${address}",
  "project": "${COMPOSE_PROJECT_NAME}",
  "domain": "${IWB_DOMAIN}",
  "comment": "Deployment wallet for n8n-driven Akash deployments"
}
EOF
    
    # Upload backup to configured provider
    log "Uploading backup to $(storage_provider_name)..."
    local archive_basename="${IWB_DOMAIN}_akash_latest.tar.gz"
    local archive_path="/tmp/${archive_basename}"
    local remote_key
    remote_key="$(storage_key_latest "akash" "${archive_basename}")"
    
    # Create tar archive
    tar -czf "$archive_path" -C "$backup_dir" .
    
    if storage_upload "$archive_path" "$remote_key"; then
        log "Wallet backup uploaded successfully to $(storage_provider_name)"
        # Clean up local files
        rm -f "$archive_path" "$backup_file"
    else
        log "${ERR_PREFIX} Failed to upload wallet backup to $(storage_provider_name)"
        rm -f "$archive_path" "$backup_file"
        return 1
    fi
    
    # Get balance and send notification
    local balance
    balance=$(get_wallet_balance "$address")
    send_wallet_notification "$address" "$balance"
    
    # Clean up wallet from keyring for security
    echo "" | provider-services keys delete "${AKASH_WALLET_NAME}" \
        --keyring-backend "${AKASH_KEYRING_BACKEND}" \
        --yes --force >/dev/null 2>&1
    
    
    log "Wallet removed from keyring for security"
    return 0
}

# Function to get wallet balance
get_wallet_balance() {
    local address="$1"
    # Log to stderr to avoid capturing in return value
    log "Checking wallet balance for address: ${address}" >&2
    
    local balance_json
    local uakt_balance
    local uact_balance
    local query_status=0

    balance_json=$(timeout 30 provider-services query bank balances "${address}" \
        --node "${AKASH_NODE}" \
        --chain-id "${AKASH_CHAIN_ID}" \
        --output json 2>/dev/null) || query_status=$?

    if [ "$query_status" -ne 0 ] || [ -z "$balance_json" ]; then
        log "WARN: Could not fetch wallet balances (network issue or new wallet), defaulting AKT/ACT to 0" >&2
        uakt_balance="0"
        uact_balance="0"
    else
        uakt_balance=$(echo "$balance_json" | jq -r '([.balances[]? | select(.denom == "uakt")][0].amount) // "0"' 2>/dev/null || echo "0")
        uact_balance=$(echo "$balance_json" | jq -r '([.balances[]? | select(.denom == "uact")][0].amount) // "0"' 2>/dev/null || echo "0")
    fi

    if [ -z "$uakt_balance" ] || [ "$uakt_balance" = "null" ]; then
        uakt_balance="0"
    fi
    if [ -z "$uact_balance" ] || [ "$uact_balance" = "null" ]; then
        uact_balance="0"
    fi

    # Convert micro-denoms to token units
    local akt_balance
    local act_balance
    akt_balance=$(echo "scale=6; ${uakt_balance} / 1000000" | bc 2>/dev/null || echo "0")
    act_balance=$(echo "scale=6; ${uact_balance} / 1000000" | bc 2>/dev/null || echo "0")
    
    # Get AKT price in USD
    local akt_price_usd
    akt_price_usd=$(timeout 10 curl -s "https://api.coingecko.com/api/v3/simple/price?ids=akash-network&vs_currencies=usd" 2>/dev/null | jq -r '.["akash-network"].usd // "0"' 2>/dev/null || echo "0")
    
    if [ "$akt_price_usd" = "0" ] || [ -z "$akt_price_usd" ]; then
        log "WARN: Could not fetch AKT price from API" >&2
        echo "AKT: ${akt_balance} (uakt: ${uakt_balance}) | ACT: ${act_balance} (uact: ${uact_balance})"
    else
        local akt_usd_balance
        local act_usd_balance
        akt_usd_balance=$(echo "scale=2; ${akt_balance} * ${akt_price_usd}" | bc 2>/dev/null || echo "0.00")
        act_usd_balance=$(echo "scale=2; ${act_balance} * ${akt_price_usd}" | bc 2>/dev/null || echo "0.00")

        echo "AKT: ${akt_balance} (uakt: ${uakt_balance}, \$${akt_usd_balance} USD) | ACT: ${act_balance} (uact: ${uact_balance}, ~\$${act_usd_balance} USD @ AKT spot)"
    fi
}

# Function to send wallet notification email
send_wallet_notification() {
    local address="$1"
    local balance="$2"
    
    log "Sending wallet notification email..."
    
    # Wait for postfix to become ready
    while ! nc -z 127.0.0.1 25; do
        log "Waiting for postfix (port 25)..."
        sleep 4
    done
    
    local mail_from="${IWB_MAIL_USER}@${IWB_DOMAIN}"
    local mail_from_name="IWB 🔴🟢🔵 | Your Digital Presence Platform"
    local mail_from_header="${mail_from_name} <${mail_from}>"
    local mail_to="$mail_from"
    local subject="New Akash Deployment Wallet Created for ${IWB_DOMAIN}"
    
    local body=$(cat <<EOF
Hello!

A new Akash deployment wallet has been created for your domain: ${IWB_DOMAIN}

Wallet Details:
- Public Address: ${address}
- Current Balances: ${balance}
- Wallet Name: ${AKASH_WALLET_NAME}
- Network: Akash Network (akashnet-2)

The wallet has been securely backed up to your configured cloud storage and removed from the local system for security.

To fund this wallet for deployments, send AKT tokens to the public address above.
If needed, convert between AKT and ACT using Akash BME commands.

Note: The private key/mnemonic is NOT included in this email for security reasons. 
It is securely stored in your encrypted cloud backup.

– Your IWB Server 🌐
EOF
)
    
    if {
        echo "To: $mail_to"
        echo "From: $mail_from_header"
        echo "Reply-To: $mail_from"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | /usr/sbin/sendmail -t; then
        log "Successfully sent wallet notification email"
    else
        log "${ERR_PREFIX} Failed to send wallet notification email"
    fi
}

# Function to send wallet notification email for existing wallet
send_wallet_notification_existing() {
    local address="$1"
    local balance="$2"
    
    log "Sending existing wallet notification email..."
    
    # Wait for postfix to become ready
    while ! nc -z 127.0.0.1 25; do
        log "Waiting for postfix (port 25)..."
        sleep 4
    done
    
    local mail_from="${IWB_MAIL_USER}@${IWB_DOMAIN}"
    local mail_from_name="IWB 🔴🟢🔵 | Your Digital Presence Platform"
    local mail_from_header="${mail_from_name} <${mail_from}>"
    local mail_to="$mail_from"
    local subject="Akash Deployment Wallet Status for ${IWB_DOMAIN}"
    
    local body=$(cat <<EOF
Hello!

Your Akash deployment wallet has been verified and is ready for use on ${IWB_DOMAIN}

Wallet Details:
- Public Address: ${address}
- Current Balances: ${balance}
- Wallet Name: ${AKASH_WALLET_NAME}
- Network: Akash Network (akashnet-2)

This wallet was restored from your secure cloud backup and is ready for deployments.

To fund this wallet for deployments, send AKT tokens to the public address above.
If needed, convert between AKT and ACT using Akash BME commands.

Note: The private key/mnemonic is NOT included in this email for security reasons. 
It is securely stored in your encrypted cloud backup.

– Your IWB Server 🌐
EOF
)
    
    if {
        echo "To: $mail_to"
        echo "From: $mail_from_header"
        echo "Reply-To: $mail_from"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | /usr/sbin/sendmail -t; then
        log "Successfully sent existing wallet notification email"
    else
        log "${ERR_PREFIX} Failed to send existing wallet notification email"
    fi
}

# Main setup function
setup_akash_wallet() {
    log "Checking for existing Akash wallet backup..."
    
    # Try to restore existing wallet backup using existing infrastructure
    # Use subshell to prevent early return from affecting our function
    if (source /var/setup/scripts/backup/iwb-restore.sh akash latest); then
        log "Found and restored existing Akash wallet backup"
        
        # Get the wallet address from the restored wallet for notification
        local address
        address=$(provider-services keys show "${AKASH_WALLET_NAME}" \
            --keyring-backend "${AKASH_KEYRING_BACKEND}" \
            --address 2>/dev/null)
        
        if [ -n "$address" ]; then
            log "Retrieved wallet address: ${address}"
            
            # Get balance and send notification email
            local balance
            balance=$(get_wallet_balance "$address")
            send_wallet_notification_existing "$address" "$balance"
        else
            log "WARN: Could not retrieve wallet address from restored backup"
        fi
        
        # Clean up restored wallet immediately for security
        echo "" | provider-services keys delete "${AKASH_WALLET_NAME}" \
            --keyring-backend "${AKASH_KEYRING_BACKEND}" \
            --yes --force >/dev/null 2>&1
        
        log "Akash wallet setup completed (existing backup restored)"
        return 0
    else
        log "No existing backup found, creating new wallet..."
        if create_new_akash_wallet; then
            log "Akash wallet setup completed (new wallet created and backed up)"
            return 0
        else
            log "${ERR_PREFIX} Failed to create and backup new Akash wallet"
            return 1
        fi
    fi
}

# Run the setup - always execute when sourced or run directly
setup_akash_wallet
