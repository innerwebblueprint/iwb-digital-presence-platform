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
# Optional operator endpoints are tried before endpoints discovered from the registry.
AKASH_NODE="${AKASH_NODE:-}"
AKASH_REST_ENDPOINTS="${AKASH_REST_ENDPOINTS:-}"
AKASH_CHAIN_ID="akashnet-2"

format_decimal_6() {
    local value="$1"
    awk -v n="${value:-0}" 'BEGIN { printf "%.6f", (n + 0) }'
}

format_decimal_2() {
    local value="$1"
    awk -v n="${value:-0}" 'BEGIN { printf "%.2f", (n + 0) }'
}

initialize_storage_provider_for_akash() {
    local max_attempts=5
    local delay_seconds=6
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        if source /var/setup/scripts/storage-providers/storage-router.sh; then
            MODULE="AKASH WALLET"
            log "Storage provider ready for Akash wallet setup (attempt ${attempt}/${max_attempts})"
            return 0
        fi

        MODULE="AKASH WALLET"
        log "WARN: Storage provider initialization failed for Akash wallet setup (attempt ${attempt}/${max_attempts})"
        attempt=$((attempt + 1))
        sleep "$delay_seconds"
    done

    MODULE="AKASH WALLET"
    return 1
}

send_wallet_failure_notification() {
    local reason="$1"

    local smtp_wait_seconds=0
    while ! nc -z 127.0.0.1 25; do
        smtp_wait_seconds=$((smtp_wait_seconds + 2))
        if [ "$smtp_wait_seconds" -ge 120 ]; then
            log "WARN: Postfix not ready after ${smtp_wait_seconds}s; skipping Akash failure notification email"
            return 0
        fi
        sleep 2
    done

    local mail_from="${IWB_MAIL_USER}@${IWB_DOMAIN}"
    local mail_from_name="=?UTF-8?B?SVdCIPCflLTwn5+i8J+UtSB8IFlvdXIgRGlnaXRhbCBQcmVzZW5jZSBQbGF0Zm9ybQ==?="
    local mail_from_header="${mail_from_name} <${mail_from}>"
    local mail_to="$mail_from"
    local subject="Akash Wallet Setup Warning for ${IWB_DOMAIN}"

    local body
    body=$(cat <<EOF
Hello!

Akash wallet startup setup did not complete successfully for ${IWB_DOMAIN}.

Reason:
- ${reason}

No Akash wallet status email could be generated from backup at this startup.
You can re-run the setup manually inside the container:

  source /var/setup/scripts/setup-akash-wallet.sh

– Your IWB Server 🌐
EOF
)

    if {
        echo "To: $mail_to"
        echo "From: $mail_from_header"
        echo "Subject: $subject"
        echo "Date: $(LC_ALL=C date -R)"
        echo "Message-Id: <akash.$(date +%s).$$@mail.${IWB_DOMAIN}>"
        echo "MIME-Version: 1.0"
        echo "Auto-Submitted: auto-generated"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | /usr/sbin/sendmail -t -f "$mail_from"; then
        log "Sent Akash wallet failure notification email"
    else
        log "WARN: Failed to send Akash wallet failure notification email"
    fi
}

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

# Require a real bank response; error JSON must never become a zero balance.
valid_bank_balances() {
    jq -e '(.balances | type == "array") and
        all(.balances[]; (.denom | type == "string") and
            (.amount | type == "string") and (.amount | test("^[0-9]+$")))' >/dev/null 2>&1
}

# All discovery and endpoint requests share a 120-second startup budget.
akash_http_get() {
    local remaining=$((akash_lookup_deadline - SECONDS))
    [ "$remaining" -gt 0 ] || return 124
    [ "$remaining" -le 10 ] || remaining=10
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 3 --max-time "$remaining" "$@"
}

discover_akash_endpoints() {
    local registry_url registry endpoint
    local -a registry_urls=(
        'https://raw.githubusercontent.com/akash-network/net/main/mainnet/meta.json'
        'https://github.com/akash-network/net/raw/refs/heads/main/mainnet/meta.json'
    )
    for registry_url in "${registry_urls[@]}"; do
        if registry=$(akash_http_get "$registry_url") &&
            jq -e --arg chain "$AKASH_CHAIN_ID" '
                .chain_id == $chain and (.apis.rpc | type == "array") and
                (.apis.rest | type == "array")' <<< "$registry" >/dev/null 2>&1; then
            # Treat the downloaded registry as data; allow only HTTPS URLs without whitespace.
            while IFS= read -r endpoint; do
                if [[ " ${akash_rpc_endpoints[*]} " != *" $endpoint "* ]]; then
                    akash_rpc_endpoints+=("$endpoint")
                fi
            done < <(jq -r '.apis.rpc[].address | select(type == "string") |
                sub("/+$"; "") | select(test("^https://[^/[:space:]]+[^[:space:]]*$"))' <<< "$registry")
            while IFS= read -r endpoint; do
                if [[ " ${akash_rest_endpoints[*]} " != *" $endpoint "* ]]; then
                    akash_rest_endpoints+=("$endpoint")
                fi
            done < <(jq -r '.apis.rest[].address | select(type == "string") |
                sub("/+$"; "") | select(test("^https://[^/[:space:]]+[^[:space:]]*$"))' <<< "$registry")
            if [ "${#akash_rpc_endpoints[@]}" -gt 0 ] || [ "${#akash_rest_endpoints[@]}" -gt 0 ]; then
                log "Discovered ${#akash_rpc_endpoints[@]} RPC and ${#akash_rest_endpoints[@]} REST candidates from ${registry_url}" >&2
                return 0
            fi
        fi
        log "WARN: Could not load valid Akash endpoint registry from ${registry_url}" >&2
    done
    log "WARN: Registry discovery failed; only operator-configured endpoints are available" >&2
    return 1
}

get_wallet_balances_rpc() {
    local address="$1" endpoint health response remaining
    # Reserve half the overall budget for REST if CLI/RPC queries keep failing.
    local rpc_deadline=$((SECONDS + 60))
    [ "$rpc_deadline" -le "$akash_lookup_deadline" ] || rpc_deadline=$akash_lookup_deadline
    local akash_lookup_deadline=$rpc_deadline
    for endpoint in "${akash_rpc_endpoints[@]}"; do
        [ "$SECONDS" -lt "$akash_lookup_deadline" ] || break
        # --chain-id on a query alone does not verify the remote network.
        if ! health=$(akash_http_get "${endpoint%/}/status") ||
            ! jq -e --arg chain "$AKASH_CHAIN_ID" '
                .result.node_info.network == $chain and
                .result.sync_info.catching_up == false' <<< "$health" >/dev/null 2>&1; then
            log "WARN: RPC endpoint unhealthy, syncing, or wrong chain: ${endpoint}" >&2
            continue
        fi
        remaining=$((akash_lookup_deadline - SECONDS))
        [ "$remaining" -gt 0 ] || break
        [ "$remaining" -le 15 ] || remaining=15
        if response=$(timeout "$remaining" provider-services query bank balances "$address" \
            --node "$endpoint" --chain-id "$AKASH_CHAIN_ID" --output json) &&
            valid_bank_balances <<< "$response"; then
            log "Wallet balance retrieved via RPC ${endpoint}" >&2
            echo "$response"
            return 0
        fi
        log "WARN: RPC bank query failed at ${endpoint}; trying next endpoint" >&2
    done
    return 1
}

# Query individual denominations over REST to avoid truncated/paginated balances.
get_wallet_balances_rest() {
    local address="$1" endpoint denom response amount status attempt
    local -a amounts
    for endpoint in "${akash_rest_endpoints[@]}"; do
        [ "$SECONDS" -lt "$akash_lookup_deadline" ] || break
        if ! response=$(akash_http_get "${endpoint%/}/cosmos/base/tendermint/v1beta1/node_info") ||
            ! jq -e --arg chain "$AKASH_CHAIN_ID" '.default_node_info.network == $chain' \
                <<< "$response" >/dev/null 2>&1; then
            log "WARN: REST endpoint unavailable or wrong chain: ${endpoint}" >&2
            continue
        fi
        if ! response=$(akash_http_get "${endpoint%/}/cosmos/base/tendermint/v1beta1/syncing") ||
            ! jq -e '.syncing == false' <<< "$response" >/dev/null 2>&1; then
            log "WARN: REST endpoint unavailable or syncing: ${endpoint}" >&2
            continue
        fi
        for attempt in 1; do
            amounts=()
            for denom in uakt uact; do
                status=0
                response=$(akash_http_get --get \
                    --data-urlencode "denom=${denom}" \
                    "${endpoint%/}/cosmos/bank/v1beta1/balances/${address}/by_denom") || status=$?
                if [ "$status" -ne 0 ]; then
                    log "WARN: Balance REST query failed at ${endpoint} (${denom}, attempt ${attempt}/1, exit ${status})" >&2
                    break
                fi
                if ! amount=$(jq -er --arg denom "$denom" '
                    .balance | select(.denom == $denom) | .amount |
                    select(type == "string") | select(test("^[0-9]+$"))' <<< "$response"); then
                    log "WARN: Invalid balance REST response at ${endpoint} (${denom}, attempt ${attempt}/1)" >&2
                    break
                fi
                amounts+=("$amount")
            done
            if [ "${#amounts[@]}" -eq 2 ]; then
                log "Wallet balance retrieved via REST ${endpoint}" >&2
                jq -n --arg akt "${amounts[0]}" --arg act "${amounts[1]}" \
                    '{balances: [{denom: "uakt", amount: $akt}, {denom: "uact", amount: $act}]}'
                return 0
            fi
        done
    done
    return 1
}

# Function to get wallet balance
get_wallet_balance() {
    local address="$1"
    log "Checking wallet balance for address: ${address}" >&2

    local balance_json uakt_balance uact_balance
    local akash_lookup_deadline=$((SECONDS + 120))
    local -a akash_rpc_endpoints=() akash_rest_endpoints=()
    [ -z "$AKASH_NODE" ] || akash_rpc_endpoints+=("${AKASH_NODE%/}")
    read -r -a akash_rest_endpoints <<< "$AKASH_REST_ENDPOINTS"
    discover_akash_endpoints || true
    if ! balance_json=$(get_wallet_balances_rpc "$address") &&
        ! balance_json=$(get_wallet_balances_rest "$address"); then
        log "WARN: Wallet balance endpoints exhausted or 120-second budget reached; balance unavailable" >&2
        echo "AKT: unavailable | ACT: unavailable (balance lookup failed; retry later)"
        return 0
    fi
    uakt_balance=$(jq -r '([.balances[] | select(.denom == "uakt")][0].amount) // "0"' <<< "$balance_json")
    uact_balance=$(jq -r '([.balances[] | select(.denom == "uact")][0].amount) // "0"' <<< "$balance_json")

    # Convert micro-denoms to token units
    local akt_balance
    local act_balance
    local akt_balance_raw
    local act_balance_raw
    akt_balance_raw=$(echo "scale=12; ${uakt_balance} / 1000000" | bc 2>/dev/null || echo "0")
    act_balance_raw=$(echo "scale=12; ${uact_balance} / 1000000" | bc 2>/dev/null || echo "0")
    akt_balance=$(format_decimal_6 "$akt_balance_raw")
    act_balance=$(format_decimal_6 "$act_balance_raw")
    
    # Get AKT price in USD
    local akt_price_usd
    akt_price_usd=$(timeout 10 curl --fail --silent --show-error --connect-timeout 5 --max-time 9 "https://api.coingecko.com/api/v3/simple/price?ids=akash-network&vs_currencies=usd" 2>/dev/null | jq -r '.["akash-network"].usd // "0"' 2>/dev/null || echo "0")
    
    if [ "$akt_price_usd" = "0" ] || [ -z "$akt_price_usd" ]; then
        log "WARN: Could not fetch AKT price from API" >&2
        echo "AKT: ${akt_balance} (uakt: ${uakt_balance}) | ACT: ${act_balance} (uact: ${uact_balance})"
    else
        local akt_usd_balance
        local act_usd_balance
        local akt_usd_balance_raw
        local act_usd_balance_raw
        akt_usd_balance_raw=$(echo "scale=12; ${akt_balance} * ${akt_price_usd}" | bc 2>/dev/null || echo "0")
        # ACT is a USD-pegged compute credit, so value it at approximately $1 per ACT.
        act_usd_balance_raw="$act_balance_raw"
        akt_usd_balance=$(format_decimal_2 "$akt_usd_balance_raw")
        act_usd_balance=$(format_decimal_2 "$act_usd_balance_raw")

        echo "AKT: ${akt_balance} (uakt: ${uakt_balance}, \$${akt_usd_balance} USD) | ACT: ${act_balance} (uact: ${uact_balance}, ~\$${act_usd_balance} USD)"
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
    local mail_from_name="=?UTF-8?B?SVdCIPCflLTwn5+i8J+UtSB8IFlvdXIgRGlnaXRhbCBQcmVzZW5jZSBQbGF0Zm9ybQ==?="
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
        echo "Subject: $subject"
        echo "Date: $(LC_ALL=C date -R)"
        echo "Message-Id: <akash.$(date +%s).$$@mail.${IWB_DOMAIN}>"
        echo "MIME-Version: 1.0"
        echo "Auto-Submitted: auto-generated"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | /usr/sbin/sendmail -t -f "$mail_from"; then
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
    local mail_from_name="=?UTF-8?B?SVdCIPCflLTwn5+i8J+UtSB8IFlvdXIgRGlnaXRhbCBQcmVzZW5jZSBQbGF0Zm9ybQ==?="
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
        echo "Subject: $subject"
        echo "Date: $(LC_ALL=C date -R)"
        echo "Message-Id: <akash.$(date +%s).$$@mail.${IWB_DOMAIN}>"
        echo "MIME-Version: 1.0"
        echo "Auto-Submitted: auto-generated"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | /usr/sbin/sendmail -t -f "$mail_from"; then
        log "Successfully sent existing wallet notification email"
    else
        log "${ERR_PREFIX} Failed to send existing wallet notification email"
    fi
}

# Main setup function
setup_akash_wallet() {
    if ! initialize_storage_provider_for_akash; then
        log "${ERR_PREFIX} Unable to initialize storage provider after retries; skipping Akash wallet setup"
        send_wallet_failure_notification "Storage provider initialization failed after retry attempts"
        return 1
    fi

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
