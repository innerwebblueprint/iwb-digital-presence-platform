# IWB Digital Presence Platform (IWB DPP) - AI Agent Instructions

## Project Overview
Single-container Docker platform providing self-hosted email (Postfix/Dovecot/Rspamd) + WordPress + n8n automation, designed for sovereignty-focused users. Built on Alpine Linux 3.21 with persistent S3-compatible (Storj) cloud backups for zero-data-loss deployments.

**Current Version**: `dev-b004` (first working email support tag)

## Architecture Pattern: State-Based Setup Scripts

This project uses a **modular shell script architecture** where container startup orchestrates setup based on persistent state flags:

### Entry Point Flow
1. **`start.sh`** → loads env via `setup-env.sh` → runs mode-specific setup:
   - `IWB_MODE=full`: Full stack (`setup-full.sh` orchestrates ~15 setup modules)
   - `IWB_MODE=bare-bones-email-only`: Email-only mode (`setup-mail-barebones.sh`) - *may be deprecated*
2. Final step: `supervisord` manages all services (nginx, postfix, dovecot, mariadb, php-fpm, n8n, etc.)

**Note**: `bare-bones-email-only` mode was originally designed for bootstrapping Storj accounts with domain-specific email. Consider using `full` mode for production deployments.

### Critical State Management
- **State flags** in `/var/data/state/` prevent re-initialization on restarts:
  - `db_initialized`, `postfixadmin_configured`, `postfixadmin_schema_initialized`
  - Scripts check flags before running destructive operations
- **Auto-generated passwords** persist to `/var/data/state/` if not in `.env`:
  - `iwb_mysql_root_password.txt` - MySQL root
  - `iwb_postfixadmin_sql_password.txt` - PostfixAdmin database
  - `iwb_wp_mysql_password.txt` - WordPress database
  - `iwb_rspamd_controller_password.txt` - Rspamd web UI (normal)
  - `iwb_rspamd_controller_enable_password.txt` - Rspamd web UI (enable/disable)
  - View all: `/var/setup/scripts/show-passwords.sh`

### Module Pattern (Example: `postfixadmin-setup.sh`)
```bash
# 1. Check state flag
if [ -f "$IWB_POSTFIXADMIN_CONFIGURED_FLAG" ]; then
  log "PostfixAdmin already configured. Skipping."
  return 0
fi

# 2. Attempt restore from Storj backup
if iwb-restore.sh postfix; then
  log "Restored from backup"
else
  # 3. Fresh setup logic (database, schema, default user)
fi

# 4. Set state flag
touch "$IWB_POSTFIXADMIN_CONFIGURED_FLAG"
```

## Key Developer Workflows

### Building and Deploying
```bash
# Build container (see docker-building-commands.md)
docker build -t iwbp/iwbdpp:dev-latest .
docker push iwbp/iwbdpp:dev-latest

# Deploy with docker-compose (copy templates from examples-templates/)
cp examples-templates/env.template .env
cp examples-templates/docker-compose.yml.template docker-compose.yml
# Edit .env with IWB_DOMAIN, IWB_MAIL_USER, IWB_STORJ_GRANT, etc.
docker-compose up -d
```

### Backup/Restore System (`iwb-backup.sh` / `iwb-restore.sh`)
- **Usage**: `iwb-backup.sh <dataset> <interval>` and `iwb-restore.sh <dataset> [interval]`
- **Datasets**: `mail`, `postfix`, `ssl`, `dkim`, `rspamd`, `wpdb`, `wphtml`, `n8n`, `akash`
- **Intervals**: `snapshot` (manual), `hourly`, `daily`, `weekly`, `monthly`, `yearly`
- **Storage router**: `storage-providers/storage-router.sh` abstracts cloud provider (currently Storj-only)
- Backups run via cron (configured in `setup-cron.sh`) and integrate with every setup script

### Akash Network Integration
- **Wallet management only**: Container creates/restores Akash wallet at startup, sends funding email
- **Deployment happens externally**: Actual Akash deployments handled by separate `iwb-akash-deploy` repo
- **Wallet lifecycle**: Created by `setup-akash-wallet.sh` → backed up to Storj → restored on-demand via `akash-wallet-restore.sh`
- **Security pattern**: Wallet removed from keyring after operations, only restored when needed

## Critical Conventions

### Environment Variable Hierarchy
1. User-provided via `.env` (e.g., `IWB_DOMAIN`, `IWB_MAIL_USER`)
2. Auto-generated if missing + persisted to disk (e.g., `IWB_MYSQL_ROOT_PASSWORD`)
3. Derived from COMPOSE_PROJECT_NAME (e.g., `IWB_WP_MYSQL_DATABASE="${COMPOSE_PROJECT_NAME}wpdb"`)

### Template Processing Pattern
```bash
# All configs use .template → rendered file pattern
sed -e "s|{{IWB_DOMAIN}}|$IWB_DOMAIN|g" \
    -e "s|{{PUBLIC_IP}}|$PUBLIC_IP|g" \
    "$SOURCE.template" > "$TARGET"
ln -sf "$TARGET" "$FINAL_LOCATION"  # Symlink to service location
```

### Logging Convention
```bash
MODULE="COMPONENT_NAME"
source /var/setup/scripts/setup-env.sh  # Loads log() function
log "Message here"  # Outputs: [IWB][MODULE] Message
log "$ERR_PREFIX Error message"  # Outputs: [IWB][MODULE] ERROR Error message
```

### n8n Integration Security Model (see `N8N-SECURITY-README.md`)
- n8n runs as **dedicated user (UID 9001)** with limited sudo access
- **Environment isolation**: n8n cannot access sensitive vars like `IWB_STORJ_GRANT` or `IWB_MYSQL_ROOT_PASSWORD`
- Direct access to `uplink` (Storj CLI) for storage operations
- Akash wallet restored on-demand via `akash-wallet-restore.sh` → cleanup after use
- **Akash deployments**: Use external `iwb-akash-deploy` tool (separate repo), embedded in docker image by build process and invoked by n8n workflows.

## Common File Locations
- **Setup scripts**: `includes/setup/scripts/` (start.sh, setup-full.sh, db-setup.sh, etc.)
- **Config templates**: `includes/setup/configs/{http,mail,php,wordpress,mariadb}/`
- **Backups**: `iwb-backup.sh` / `iwb-restore.sh` in `includes/setup/scripts/backup/`
- **State persistence**: `/var/data/state/` (flags, generated passwords)
- **Storj integration**: `includes/setup/scripts/storage-providers/storj/`

## Known Issues (see `issues_todo.md`)
- **n8n execution bloat**: Backups reach ~800MB due to execution history (needs trimming)
- **WordPress Media Cloud plugin**: Fails uploading 18MB+ zip/tar.gz files with `SimpleXMLElement` error (file uploads but doesn't register in media library)

## Integration Points
- **WordPress** restored from `wphtml` + `wpdb` backups or fresh install via `wp-cli`
- **PostfixAdmin** uses MySQL virtual user tables (`postfixadmin-setup.sh` handles schema + restore)
- **n8n** persists to `/var/www/html/n8n` (symlinked to `/home/n8n/.n8n`), restored from Storj on startup
- **SSL certs** managed by certbot with renewal hook (`cert-renew-hook.sh`) → backed up to Storj
- **Akash wallet** created/restored at container startup, backed up to Storj (deployments via external `iwb-akash-deploy` repo)

## When Editing Scripts
1. **Always check for state flags** before running destructive operations
2. **Use `(return 1 2>/dev/null) || exit 1`** pattern for sourced scripts to avoid killing parent shells
3. **Test backup/restore cycle** for any new persistent component
4. **Add new datasets** to `iwb-backup.sh` / `iwb-restore.sh` with corresponding Storj key in `setup-env.sh`
5. **Template processing**: Use `{{VAR_NAME}}` placeholders in `.template` files

## Philosophy Note
This platform embodies "sovereignty over dependency" — user owns their data, email, and infrastructure. Contributions should align with portability, zero vendor lock-in, and "runs forever" design goals.
