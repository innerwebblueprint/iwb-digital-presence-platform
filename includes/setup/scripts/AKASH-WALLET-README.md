# Akash Wallet Management Documentation

This documentation describes the Akash wallet management functionality added to the IWB Digital Presence Platform.

## Overview

The system automatically manages an Akash wallet for deployment purposes. The wallet is created once, backed up securely to Storj, and can be restored when needed for deployments.

## Components

### 1. `setup-akash-wallet.sh`
**Purpose**: Automatically run during container startup to check for existing wallet or create a new one.

**What it does**:
- Checks if a wallet backup exists on Storj at `sj://[bucket]/IWBDPP/akash/akash-deploy-backup.json`
- If no backup exists, creates a new Akash wallet using `provider-services`
- Backs up the wallet to Storj in JSON format
- Sends an email notification with the public address and balance
- Removes the wallet from the local keyring for security

**Backup JSON Format**:
```json
{
  "walletName": "examplecom_akashwallet",
  "mnemonic": "word1 word2 word3 ... word24",
  "createdAt": "2025-08-27T12:34:56Z",
  "network": "akash",
  "public_address": "akash1...",
  "comment": "Deployment wallet for n8n-driven Akash deployments"
}
```

### 2. `akash-wallet-restore.sh`
**Purpose**: Restore the wallet from Storj backup for use in n8n deployments.

**Usage from n8n**:
```bash
# Restore wallet and get info
/usr/local/bin/n8n-cmd akash-wallet restore

# Get wallet info (restores if needed)
/usr/local/bin/n8n-cmd akash-wallet info

# Clean up wallet after deployment
/usr/local/bin/n8n-cmd akash-wallet cleanup
```

**Return Format**: JSON output for n8n consumption (NO SENSITIVE DATA):
```json
{
  "wallet_name": "examplecom_akashwallet",
  "address": "akash1...",
  "created_at": "2025-08-27T12:34:56Z",
  "keyring_backend": "test",
  "status": "ready_for_deployment"
}
```

**Security Note**: The mnemonic/private key is never returned to n8n. The wallet is restored to the provider-services keyring and ready for use, but sensitive information remains secure.

## Security Considerations

1. **Wallet Storage**: The wallet mnemonic is only stored in the encrypted Storj backup
2. **Local Cleanup**: Wallets are automatically removed from the local keyring after creation/use
3. **Limited Access**: n8n can only call specific, validated actions through the command wrapper
4. **Email Security**: The private key/mnemonic is never sent via email
5. **No Sensitive Data Exposure**: The restore script never returns mnemonics or private keys to n8n
6. **Keyring Security**: Wallet is only temporarily restored to keyring for deployment operations

## Workflow Integration

### Typical n8n Deployment Workflow:

1. **Restore Wallet**: Call `akash-wallet restore` to restore wallet to provider-services keyring
2. **Deploy**: Use provider-services commands - the wallet is already available in the keyring
3. **Cleanup**: Call `akash-wallet cleanup` to remove wallet from keyring for security

### Example n8n Node Configuration:

**Restore Wallet Node**:
- Command: `/usr/local/bin/n8n-cmd`
- Arguments: `akash-wallet restore`
- Output: Parse JSON response to confirm wallet is ready (`status: "ready_for_deployment"`)

**Deployment Node**:
- Use provider-services commands directly - wallet is available in keyring
- Example: `provider-services tx deployment create deploy.yaml --from [wallet_name]`

**Cleanup Node**:
- Command: `/usr/local/bin/n8n-cmd`
- Arguments: `akash-wallet cleanup`

## Funding the Wallet

To fund the wallet for deployments:
1. Check the email notification for the public address
2. Send AKT tokens to that address from an external wallet
3. The balance will be available for deployments

## Troubleshooting

### Check if wallet backup exists:
```bash
uplink ls sj://[bucket]/IWBDPP/akash/akash-deploy-backup.json
```

### Manually restore wallet:
```bash
/var/setup/scripts/akash-wallet-restore.sh restore
```

### View logs:
```bash
tail -f /var/log/iwb-email.log
tail -f /var/log/n8n-commands.log
```

### Check wallet balance:
```bash
provider-services query bank balances [address] --node https://rpc.akashnet.net:443 --chain-id akashnet-2
```

## Environment Variables

The system uses these existing environment variables:
- `IWB_DOMAIN`: Used to generate unique wallet name
- `IWB_STORJ_WPOPS_BUCKET`: Storj bucket for backups
- `IWB_MAIL_USER`: Email address for notifications

## Notes

- The wallet name format is: `{domain_sanitized}akashwallet`
- The system uses `test` keyring backend for simplicity
- Wallets are automatically cleaned up after each use for security
- The system connects to Akash mainnet (akashnet-2)
