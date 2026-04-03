# Changelog

All notable changes to the IWB Digital Presence Platform will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
- `v#.#.#-dev.N` for development builds (e.g., v1.0.0-dev.1)
- `v#.#.#` for production releases (e.g., v1.0.0)

Version format:
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes (backward compatible)
- `-dev.N`: Pre-release development build number

## [Unreleased]

### Added
### Changed
### Fixed
### Removed
### Security

---

## [v1.0.0-dev.56] - 2026-04-02

> **Commit Summary:** fix(mail): align spam headers and Junk filing with live namespace and Rspamd module behavior

### Added
### Changed
### Fixed
- The default server-side spam filing rule now targets `INBOX/Junk` when that namespace exists, fixing full-mode deliveries where Dovecot rejected `fileinto "Junk"` because the mailbox name was prefixed.
- The Rspamd `milter_headers` configuration now explicitly enables the custom and extended header routines so scan-result headers are actually emitted after redeploy.
### Removed
### Security

---


---

## [v1.0.0-dev.55] - 2026-04-02

> **Commit Summary:** feat(mail): strengthen server-side spam filtering, Bayes learning, and Redis-backed persistence safety

### Added
- Rspamd now renders a dedicated `milter_headers` local config so inbound mail can carry consistent server-side scan metadata instead of only sometimes receiving spam headers.
- Dovecot now ships a default global Sieve rule that files spam-tagged mail into `Junk` before per-user filters run, enabling server-side spam filing by default in both full and bare-bones mail modes.
- Full-mode mail builds now include Dovecot IMAPSieve training hooks that teach Rspamd Bayes when users move mail into `Junk` or back out of `Junk`.
### Changed
- Mail filtering defaults now stamp scanned mail with `X-Spam-Status` plus a custom `X-IWB-Spam-Checked: yes` header so downstream rules can reliably detect that the server scanned the message.
- Full-mode Dovecot startup now renders local `rspamc` training wrappers and compiles the administrator Sieve scripts used for spam and ham learning when `sievec` is available.
- Rspamd now uses Redis database `1` by default so Bayes and related mail-filter state no longer share WordPress's default Redis database `0`.
- The `rspamd` backup dataset now stages both `/var/lib/rspamd` and `/var/dump.rdb`, and restore now extracts that Redis persistence back to `/`, preserving Bayes learning across restores.
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.54] - 2026-03-31

> **Commit Summary:** fix(storage): ignore placeholder storj env values

### Added
### Changed
- The example env template now puts Storj guidance and the initial n8n password warning on standalone comment lines so copied `.env` files do not treat those notes as literal values.
- R2-backed containers now install an `aws` wrapper that automatically uses the configured `IWB_R2_*` credentials and Cloudflare endpoint for interactive shell usage.
### Fixed
- R2 deployments now ignore placeholder/comment-only `IWB_STORJ_GRANT` values instead of attempting optional Storj initialization and failing startup.
- Storj mode still errors clearly when `storj` is selected but the access grant is missing or left at a placeholder value.
### Removed
### Security

---


---

## [v1.0.0-dev.53] - 2026-03-31

### Added
### Changed
### Fixed
- Akash wallet status emails now value `ACT` as a USD-pegged compute credit instead of incorrectly pricing it at the current `AKT` spot rate.
### Removed
### Security

---


---

## [v1.0.0-dev.52] - 2026-03-31

> **Commit Summary:** fix(security): block stray redis dump files from web access

### Added
### Changed
- WordPress Nginx vhost templates now explicitly deny direct access to `.rdb` files so accidental Redis snapshot artifacts in the web root cannot be downloaded.
- Redis configuration now explicitly pins persistence to `/var/dump.rdb` instead of relying on the process working directory.
### Fixed
- Existing exposed `dump.rdb` artifacts were traced to historical Redis persistence behavior and backup propagation rather than current plugin configuration; future builds now block web serving of those files by default.
- Future Redis snapshots are now anchored away from web content paths even if startup context changes.
### Removed
### Security

---


---

## [v1.0.0-dev.51] - 2026-03-31

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.50] - 2026-03-31

> **Commit Summary:** fix(startup): pin compatible node runtime and reuse storage init

### Added
### Changed
- Docker builds now resolve the Node.js major version required by the current stable n8n release and copy a matching official Node runtime into the final image.
- Storage provider setup now reuses exported initialization flags so repeated startup, restore, and wallet flows do not re-import and re-verify Storj/R2 credentials over and over in the same container boot.
### Fixed
- Latest stable n8n images no longer start with an unsupported Alpine Node patch release when n8n requires a newer Node version.
- Startup logs are quieter and storage initialization work is no longer repeated unnecessarily during the same container boot.
### Removed
### Security

---


---

## [v1.0.0-dev.49] - 2026-03-31

> **Commit Summary:** chore(build): remove unused python build tooling from runtime image

### Added
### Changed
- The final Docker image now keeps only the Python runtime packages needed by embedded tooling and drops unused Python packaging/build dependencies.
### Fixed
- Runtime images no longer carry the unused Python compiler and packaging toolchain, reducing image size without changing current application behavior.
### Removed
- Removed unused runtime image packages: `gcc`, `musl-dev`, `libffi-dev`, `openssl-dev`, `py3-pip`, `py3-setuptools`, and `py3-wheel`.
### Security

---


---

## [v1.0.0-dev.48] - 2026-03-31

> **Commit Summary:** refactor(build): reduce docker rebuild churn and trim image layers

### Added
### Changed
- Docker now installs Node.js/npm earlier as stable runtime dependencies and defers the versioned n8n install until late in the image so n8n bumps invalidate a much smaller tail of layers.
- The Akash `provider-services` binary is now copied with executable permissions in a single step, avoiding an extra large chmod layer.
### Fixed
- The n8n install step now uses a temporary npm cache and removes it in the same layer, reducing image bloat from persisted npm package cache files.
- Docker pushes should now avoid re-uploading as much data when only n8n changes because fewer downstream layers are invalidated.
### Removed
### Security

---


---

## [v1.0.0-dev.47] - 2026-03-31

> **Commit Summary:** fix(build): align n8n node checks with resolved version

### Added
### Changed
- Docker now checks Node.js compatibility against the exact resolved `n8n@${N8N_VERSION}` package metadata instead of reading requirements from the moving `master` branch.
### Fixed
- Docker builds now use the same resolved n8n version for both Node.js requirement validation and package installation, avoiding branch-to-package mismatch risk.
### Removed
### Security

---


---

## [v1.0.0-dev.46] - 2026-03-31

> **Commit Summary:** fix(build): cache stable n8n updates in docker builds

### Added
### Changed
- Docker builds now resolve npm's current stable `n8n` version once in `scripts/build-and-push.sh` and pass it into the Docker build as `N8N_VERSION`.
- The Dockerfile now installs `n8n@${N8N_VERSION}` instead of a floating global `n8n` package so the n8n layer remains cached until the stable version changes.
### Fixed
- Rebuilds now stay on the current stable n8n release while avoiding unnecessary n8n reinstalls and image churn on small project changes.
### Removed
### Security

---


---

## [v1.0.0-dev.45] - 2026-03-31

> **Commit Summary:** fix(storage): bootstrap optional storj access alongside r2

### Added
### Changed
- Storage startup now bootstraps Storj `uplink` access for both root and `n8n` whenever `IWB_STORJ_GRANT` is present, even if `IWB_PERSISTENT_STORAGE` is set to `r2`.
- Storj setup was refactored into reusable access-bootstrap helpers so optional secondary-provider access can be initialized without changing the active storage backend.
### Fixed
- Containers using Cloudflare R2 as the primary storage provider now still prepare in-container Storj credentials when Storj env vars are supplied, restoring legacy Storj access for workflows and manual operations.
### Removed
### Security

---


---

## [v1.0.0-dev.44] - 2026-03-31

> **Commit Summary:** fix(backup): run nightly cleanup at 2am pacific time

### Added
### Changed
- Adjusted nightly backup cleanup scheduling to run at 09:00 UTC so production containers currently operating on UTC execute cleanup at 2:00 AM Pacific daylight time.
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.43] - 2026-03-30
> **Commit Summary:** fix(storage): prevent storj delete dry-run from hanging during validation

### Added
### Changed
### Fixed
- Storage migration delete mode now prepares Storj uplink config and performs bounded validation checks so `iwb-migrate-storage.sh --delete --from storj --dry-run` does not hang during provider validation.
### Removed
### Security

---


---

## [v1.0.0-dev.42] - 2026-03-30
> **Commit Summary:** refactor(build): simplify build workflow and remove unused platform support

### Added
- Added a `--yes` option to `scripts/build-and-push.sh` so wrapper scripts can reuse the shared build/push flow non-interactively.
### Changed
- Standardized project script versioning around `v#.#.#-dev.N` for development builds and `v#.#.#` for releases.
- Refactored `scripts/dev-deploy.sh` and `scripts/release.sh` to call `scripts/build-and-push.sh` instead of maintaining separate Docker build logic.
- Narrowed the build workflow to standard Linux server targets by removing unused `--platform` support from `scripts/build-and-push.sh`.
- Updated build script documentation to match the current SemVer-based development workflow and shared build entrypoint.
### Fixed
- Removed remaining legacy `dev-b###` handling from build and release scripts so version bumps now match the repository's actual `VERSION` format.
- Shared Docker builds now consistently include the Akash deploy cache-busting build arg because wrapper scripts reuse `scripts/build-and-push.sh`.
### Removed
### Security

---


---

## [v1.0.0-dev.41] - 2026-03-30

> **Commit Summary:** refactor(build): unify semver dev versioning and centralize docker builds

### Added
- Added a `--yes` option to `scripts/build-and-push.sh` so wrapper scripts can reuse the shared build/push flow non-interactively.
### Changed
- Standardized project script versioning around `v#.#.#-dev.N` for development builds and `v#.#.#` for releases.
- Refactored `scripts/dev-deploy.sh` and `scripts/release.sh` to call `scripts/build-and-push.sh` instead of maintaining separate Docker build logic.
- Updated build script documentation to match the current SemVer-based development workflow and shared build entrypoint.
### Fixed
- Removed remaining legacy `dev-b###` handling from build and release scripts so version bumps now match the repository's actual `VERSION` format.
- Shared Docker builds now consistently include the Akash deploy cache-busting build arg because wrapper scripts reuse `scripts/build-and-push.sh`.
### Removed
### Security

---

## [v1.0.0-dev.40] - 2026-03-30

> **Commit Summary:** fix(backup): restore cleanup execution and tighten retention pruning

### Added
### Changed
- Nightly backup cleanup cron now invokes the cleanup script by absolute path and refreshes the cleanup crontab entry on setup so stale entries do not persist.
- Startup now exposes `iwb-backup-cleanup.sh` alongside the other backup helpers for direct shell use.
- Snapshot pruning is now age-based, deleting versioned snapshots older than 7 days instead of using a fixed-count retention.
### Fixed
- Backup pruning now reliably enforces the intended versioned retention policy for daily, weekly, and monthly intervals once the container is rebuilt with the corrected cleanup wiring.
### Removed
### Security

---

## [v1.0.0-dev.39] - 2026-03-30

> **Commit Summary:** fix(akash): retry storage init and send wallet setup failure warning

### Added
- Added an explicit Akash wallet warning email when startup cannot complete wallet setup after storage-provider retry attempts, so failures are visible instead of silent.
### Changed
- Akash wallet startup now retries storage-provider initialization before restore/create operations to better tolerate transient storage readiness issues during concurrent startup tasks.
### Fixed
### Removed
### Security

---

## [v1.0.0-dev.38] - 2026-03-30

> **Commit Summary:** feat(storage): add guarded source-delete mode to storage migration utility

### Added
- Added `--delete` mode to `includes/setup/scripts/storage-providers/migrate-storage.sh` so operators can remove migrated backup archives from the old provider after verification.
- Added interactive `DELETE` confirmation for non-dry-run delete operations to reduce accidental destructive use.
### Changed
- Extended the storage migration utility to support provider-native object deletion for both Storj and Cloudflare R2.
- Refactored prefix processing in the migration utility into shared helpers so copy and delete flows stay aligned.
### Fixed
### Removed
### Security

---

## [v1.0.0-dev.37] - 2026-03-28

> **Commit Summary:** fix(akash): enforce latest-only build and add AKT/ACT balance reporting

### Added
### Changed
- Akash `provider-services` build path now uses an upstream-aligned Alpine-compatible compile flow for latest releases, including wasmvm musl static library resolution and CGO-enabled external linking.
- Akash wallet notification emails now report both token balances (`AKT` from `uakt` and `ACT` from `uact`) from live `provider-services query bank balances` output.
### Fixed
- Removed Akash fallback-to-older-tag behavior; Docker build now enforces strict `AKASH_VERSION=latest` and fails fast if the latest upstream tag is not buildable.
- Added required runtime dependency (`eudev-libs`) for latest Akash binary compatibility in the final image.
- Akash balance parsing no longer assumes the first bank balance entry is `uakt`; balances are now denom-specific to support post-upgrade ACT-enabled wallets.
- Akash balance display formatting now consistently renders leading-zero token values (for example `0.543312`) and stable USD precision in notification emails.
### Removed
### Security

---

## [v1.0.0-dev.36] - 2026-03-27

> **Commit Summary:** fix(build): keep akash latest mode resilient with auto-fallback to newest buildable release

### Added
### Changed
- Akash source build now keeps `AKASH_VERSION=latest` semantics while automatically scanning recent non-prerelease provider tags and compiling the newest tag that builds successfully.
- Akash builder now uses upstream-aligned build tags (`osusergo,netgo,muslc,gcc`) and records the resolved compiled tag in `/build/provider-services.version`.
### Fixed
- Docker builds no longer hard-fail when the newest Akash release tag is temporarily unbuildable upstream; build flow now degrades gracefully to the next buildable recent release.
### Removed
### Security

---

## [v1.0.0-dev.35] - 2026-03-27

> **Commit Summary:** fix(build): stabilize akash source build and raise wordpress upload limit

### Added
### Changed
- Increased WordPress upload ceiling to `350M` by aligning Nginx `client_max_body_size` and PHP `upload_max_filesize`/`post_max_size` limits.
- Akash `provider-services` source-build stage now uses a newer Go toolchain and robust release tag resolution to avoid upstream build breakage during Docker builds.
### Fixed
### Removed
### Security

---

## [v1.0.0-dev.34] - 2026-03-27

> **Commit Summary:** feat: add default rspamd anti-spam tuning templates and setup wiring

### Added
- New Rspamd local config templates for stronger server-side spam mitigation:
  - `includes/setup/configs/mail/rspamd/actions.conf.template`
  - `includes/setup/configs/mail/rspamd/settings.conf.template`
  - `includes/setup/configs/mail/rspamd/redis.conf.template`
  - `includes/setup/configs/mail/rspamd/greylist.conf.template`
  - `includes/setup/configs/mail/rspamd/classifier-bayes.conf.template`
### Changed
- `includes/setup/scripts/setup-rspamd.sh` now renders and symlinks Rspamd local overrides for actions, recipient-scoped settings, Redis, greylisting, and Bayes classifier Redis server binding.
### Fixed
- Default Rspamd bootstrap now includes explicit local Redis and greylist configuration templates to reduce "module enabled but unconfigured" drift across deployments.
### Removed
### Security

---

## [v1.0.0-dev.33] - 2026-03-27

> **Commit Summary:** feat: add provider-neutral storage with cloudflare r2 support

### Added
- Provider-neutral storage abstraction script: `includes/setup/scripts/storage-providers/storage-functions.sh`.
- Cloudflare R2 backend setup and operations scripts:
  - `includes/setup/scripts/storage-providers/r2/r2-setup.sh`
  - `includes/setup/scripts/storage-providers/r2/r2-functions.sh`
- Storage migration utility with resume-state and verification:
  - `includes/setup/scripts/storage-providers/migrate-storage.sh`
- Startup symlink command for migration utility: `iwb-migrate-storage.sh`.
### Changed
- Extended storage router to support `IWB_PERSISTENT_STORAGE=r2` alongside `storj`.
- Refactored backup and restore runtime to use provider-neutral storage operations:
  - `includes/setup/scripts/backup/iwb-backup.sh`
  - `includes/setup/scripts/backup/iwb-restore.sh`
- Refactored backup cleanup flow to use provider-neutral list/delete operations:
  - `includes/setup/scripts/backup/iwb-backup-cleanup.sh`
- Refactored Akash wallet backup upload path to use configured cloud provider instead of Storj-only logic.
- Updated environment bootstrap logic to validate provider-specific variables and expose unified storage aliases.
- Updated n8n minimal environment export to include provider-neutral storage variables while preserving legacy compatibility.
- Updated environment template with Cloudflare R2 credential variables and provider option guidance.
- Updated Docker image package install to include `aws-cli` for R2 S3-compatible operations.
- Added local development SSL fallback controls (`IWB_LOCAL_DEV`, `IWB_SSL_SELF_SIGNED_FALLBACK`) and self-signed certificate generation path when cloud cert restore fails.
- Added feature-scoped Docker build tagging option (`--feature-tag`) to avoid overwriting `dev-latest` during branch testing.
- Media reverse proxy configuration is now provider-neutral, with endpoint/host variables supporting both Storj and Cloudflare R2 media URL patterns.
- Added dedicated `IWB_R2_MEDIA_BUCKET` support so R2 media proxy defaults can target a separate media bucket from backup/storage buckets.
- Added explicit Storj/R2 media public base URL env parity (`IWB_STORJ_MEDIA_PUBLIC_BASE_URL`, `IWB_R2_MEDIA_PUBLIC_BASE_URL`) for consistent configuration across providers.
- Updated `env.template` with prebuilt Storj/R2 media URL examples while keeping override variables blank by default so runtime auto-derivation remains the default behavior.
- Local mode (`IWB_LOCAL_DEV=true`) now disables IWB automated cron schedule setup and removes existing IWB cron entries to prevent local instances from running backup/cleanup schedules.
- Cert domain selection now automatically skips `<project>media.<domain>` when `IWB_PERSISTENT_STORAGE=r2` and `IWB_R2_MEDIA_PUBLIC_BASE_URL` is explicitly set (non-empty), avoiding ACME conflicts with externally managed media TLS.
### Fixed
- Local self-signed TLS fallback now generates/validates `ssl-dhparams.pem` at modern strength (>=2048-bit) to prevent Nginx startup failure with `dh key too small`.
- SSL cert issuance now retries once when certbot hits transient ACME `No such authorization` errors, and logs the requested domain set for easier troubleshooting.
- Mail auth bootstrap now treats blank/comment placeholder password env values as empty before auto-generation, preventing Dovecot SQL auth from using `password=#...` and failing with `using password: NO`.
### Removed
### Security

---

## [v1.0.0-dev.32] - 2026-02-16

> **Commit Summary:** fix: make startup notification email resilient to SMTP timing and empty user query exits

### Added
### Changed
- Standardized notification sender identity across startup, credentials, DKIM, Akash wallet, and cert-renew emails to: `IWB 🔴🟢🔵 | Your Digital Presence Platform`.
### Fixed
- Startup email sender now waits for local Postfix (`127.0.0.1:25`) before attempting `/usr/sbin/sendmail -t`.
- Prevented premature script exit caused by `set -e` when role query output is empty during WordPress admin/editor list aggregation.
- Startup email script now initializes environment before first log call and exits safely when SMTP never becomes ready.
### Removed
### Security

---


---

## [v1.0.0-dev.31] - 2026-02-16

> **Commit Summary:** fix: harden startup email WordPress admin/editor user lookup

### Added
### Changed
- Startup notification email now handles WP-CLI role query failures explicitly and logs lookup errors instead of silently suppressing them.
### Fixed
- Startup email WordPress admin/editor table no longer incorrectly reports no users when role-filter queries fail transiently.
- Added fallback user discovery path (`wp user list` all users + role filtering) when direct `--role` queries return empty results.
### Removed
### Security

---


---

## [v1.0.0-dev.30] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.29] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.28] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.27] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.26] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.25] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.24] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.23] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.22] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.21] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.20] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.19] - 2025-12-26

> **Commit Summary:** feat: compile Pigeonhole with ereject support for protocol-level email rejection

### Added
- Custom Pigeonhole build with `ereject` extension support
  - Added Stage 2 builder to Dockerfile to compile Pigeonhole from source
  - Enabled unfinished extensions via `--enable-unfinished-features` flag
  - `ereject` command now available for protocol-level message rejection (never accepts message)
- ManageSieve service configuration in dovecot-99-full.conf.template
  - Added 'sieve' protocol to Dovecot protocols list
  - Added service managesieve-login listener on port 4190
  - Added service managesieve daemon for filter management
- Sieve plugin enabled for LMTP delivery protocol
  - Added `protocol lmtp { mail_plugins = $mail_plugins sieve }` configuration
  - Sieve filters now execute during mail delivery
- Users can now manage server-side Sieve filters via email clients
- Filters stored in user home directories (~/.dovecot.sieve)
- Comprehensive Sieve extension support including reject, ereject, fileinto, vacation, regex, variables, etc.

### Changed
- Replaced Alpine's dovecot-pigeonhole-plugin with custom-compiled version
- Dovecot password authentication disabled debug password logging (`auth_debug_passwords = no`)
- WordPress admin/editor user listing in startup email now correctly fetches users separately per role

### Fixed
- ManageSieve authentication with PostfixAdmin password hashes (uses standard crypt() format)
- WordPress user list in startup email (WP-CLI `--role` doesn't support comma-separated values)
- Sieve reject behavior: `reject` command sends bounce after accepting (unsafe), `ereject` rejects at SMTP/LMTP protocol level (safe)

### Removed
### Security
- Passwords no longer logged in Dovecot debug output
- `ereject` provides protocol-level rejection preventing message acceptance (vs `reject` which accepts then bounces)

**Technical Note:** Alpine's dovecot-pigeonhole-plugin doesn't include `ereject` because it's marked as UNFINISHED in Pigeonhole source (wrapped in `#ifdef HAVE_SIEVE_UNFINISHED`). We now compile from source with this flag enabled to provide proper protocol-level rejection capabilities.

---


---

## [v1.0.0-dev.18] - 2025-12-26

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.17] - 2025-12-25

> **Commit Summary:** fix: enable Sieve ereject extension

### Added
- Sieve `ereject` extension support for safe message rejection at SMTP protocol level
  - Added to `managesieve_sieve_capability` in dovecot-99-full.conf.template

### Changed
### Fixed
### Removed
- Deprecated `reject` extension from Sieve capabilities (replaced by safer `ereject`)
  - Enforces security best practice: `ereject` always rejects at SMTP level before delivery
  - Prevents unsafe `reject` behavior that may leak message content

### Security

---


---

## [v1.0.0-dev.16] - 2025-12-25

> **Commit Summary:** fix: resolve Dovecot authentication and startup email WordPress user listing

### Added
### Changed
- Dovecot SQL password query now returns raw password hash without prefix modification
  - PostfixAdmin passwords already contain `$1$` MD5-CRYPT format identifier
  - Removed incorrect `CONCAT('{MD5-CRYPT}', password)` wrapper

### Fixed
- Dovecot authentication for IMAP/POP3/ManageSieve now works correctly
  - Password hash comparison fixed by removing redundant scheme prefix
  - Dovecot `default_pass_scheme = MD5-CRYPT` properly validates `$1$` prefixed hashes
- WordPress admin/editor user list in startup email now displays correctly
  - Fixed WP-CLI command: `--role=administrator,editor` (invalid) → separate queries per role
  - Now fetches administrators and editors separately, then combines results

### Removed
### Security

---


---

## [v1.0.0-dev.15] - 2025-12-25

> **Commit Summary:** fix: correct Dovecot password authentication and disable password logging

### Added
- ManageSieve service configuration in dovecot-99-full.conf.template
  - Added 'sieve' protocol to Dovecot protocols list
  - Added service managesieve-login listener on port 4190
  - Added service managesieve daemon for filter management
- Users can now manage server-side Sieve filters via email clients (Thunderbird, Roundcube)
- Filters stored in user home directories (~/.dovecot.sieve)

### Changed
- Dovecot SQL password query now uses `CONCAT('{CRYPT}', password)` to properly identify pre-hashed passwords
- Changed `default_pass_scheme` from `MD5-CRYPT` to `CRYPT` for broader crypt() format support

### Fixed
- ManageSieve/IMAP/POP3 authentication failures caused by password scheme mismatch
  - Dovecot now correctly validates passwords hashed by PostfixAdmin's PHP crypt() function
  - Password query prepends `{CRYPT}` prefix to indicate stored hash format
- Disabled `auth_debug_passwords` to prevent plaintext passwords from appearing in logs

### Removed
### Security
- Passwords no longer logged in Dovecot debug output (auth_debug_passwords = no)
### Security

---


---

## [v1.0.0-dev.14] - 2025-12-16

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.13] - 2025-12-16

> **Commit Summary:** fix: re-enable n8n Execute Command node disabled in v2.0.2+

### Fixed
- n8n v2.0.2+ compatibility: Execute Command node now available after correcting environment variable
  - Changed from incorrect `N8N_NODES_EXCLUDE=""` to proper `NODES_EXCLUDE="[]"`
  - Variable name must be `NODES_EXCLUDE` (without N8N_ prefix) per official n8n documentation
  - Empty array format `"[]"` required to disable default node exclusion list
  - Diagnostic script added at `includes/setup/scripts/diagnose-n8n-nodes.sh` for troubleshooting

### Technical Details
**Root Cause**: n8n v2.0+ excludes "dangerous" nodes by default for security (Execute Command, Local File Trigger). Default exclusion: `NODES_EXCLUDE='["n8n-nodes-base.executeCommand", "n8n-nodes-base.localFileTrigger"]'`

**Solution**: Set `NODES_EXCLUDE="[]"` in supervisord configuration to override default exclusion list and enable all nodes. The variable name does NOT use the `N8N_` prefix despite other n8n environment variables following that pattern.

**Reference**: https://docs.n8n.io/2-0-breaking-changes/#disable-executecommand-and-localfiletrigger-nodes-by-default

---


---

## [v1.0.0-dev.12] - 2025-12-16

> **Commit Summary:** fix: compile Akash provider-services from source for Alpine/musl compatibility

### Added
- Multi-stage Docker build for Akash provider-services binary compilation
- Support for semver development version format in build-and-push.sh (v#.#.#-dev.#)

### Changed
- Akash provider-services now compiled from source instead of using pre-built binaries
- Build process uses Go 1.23+ with GOTOOLCHAIN=auto for version compatibility
- Static binary compilation with tags "osusergo,netgo,static_build"

### Fixed
- Akash provider-services binary execution on Alpine Linux (musl libc)
- Issue where Akash v0.10.5+ binaries compiled for glibc failed with "cannot execute: required file not found"
- Build bloat by separating Go build stage from final runtime image

### Technical Details
**Root Cause**: Akash provider-services v0.10.5+ (released Nov 26, 2025) binaries are compiled for Ubuntu/glibc with C23 standard library functions (`__isoc23_strtoul`) that don't exist in Alpine's musl libc.

**Solution**: Multi-stage build compiles provider-services from source in a golang:1.23-alpine builder stage, then copies only the static binary to the final Alpine runtime image. This ensures musl compatibility while keeping image size minimal.

---


---

## [v1.0.0-dev.11] - 2025-12-15

> **Commit Summary:** feat: add backup 'all' function, cleanup script, and comprehensive scheduled backups with per-instance randomization

### Added
- `iwb-backup.sh`: Added 'all' dataset parameter to backup all components (mail, postfix, ssl, dkim, rspamd, wpdb, wphtml, n8n) sequentially with full status reporting
- `iwb-backup-cleanup.sh`: New automated cleanup script with configurable retention policy:
  - Snapshot: keep 5 most recent
  - Hourly: skipped (rotation via overwrites, ~24 keys naturally maintained)
  - Daily: keep 7 most recent
  - Weekly: keep 4 most recent
  - Monthly: keep 12 most recent
  - Yearly: keep 10 most recent
  - Supports `--dry-run` flag and per-dataset/interval cleanup
  - Operates only on versioned Storj paths, never touches `latest/` objects
  - Retention counts overridable via `IWB_RETENTION_<INTERVAL>` env vars
- `setup-cron.sh`: Comprehensive backup scheduling added:
  - Daily backups for all datasets (02:00–02:59 window)
  - Weekly backups (Sunday, 02:00–03:59 window)
  - Monthly backups (1st of month, 03:00–03:59 window)
  - Yearly backups (Jan 1, 03:00–04:59 window)
  - Nightly cleanup job (04:00–04:59 window)
- Per-instance randomized cron staggering to prevent synchronized runs across multiple IWBDPP instances on shared hosts
  - `compute_offset()` function generates deterministic minute offsets based on `IWB_DOMAIN` hash
  - Distributes load across 10+ instances without coordination

### Changed
- `setup-cron.sh`: All backup cron jobs now use randomized minute offsets instead of fixed times to avoid resource contention
- Hourly backup jobs spread across 10-minute windows per dataset

### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.10] - 2025-12-15

> **Commit Summary:** fix: ensure certbot renew deploy-hook reloads mail services (stale IMAP cert)

### Added
- Installing some new fonts.
### Changed
### Fixed
- Certbot deploy-hook (`cert-renew-hook.sh`) no longer hard-depends on `IWB_*` env vars; it now uses certbot-provided `RENEWED_LINEAGE/RENEWED_DOMAINS` and writes a persistent hook log.
- Mail TLS now refreshes correctly after renew: Dovecot/Postfix are reloaded/restarted so IMAP clients (e.g., Thunderbird) see the renewed certificate instead of a stale/expired one.
### Removed
### Security

---


---

## [v1.0.0-dev.9] - 2025-11-20

> **Commit Summary:** fix: XML errors; prevent n8n backups from interrupting active workflow executions

### Added
- PHP XML packages: `php83-simplexml` and `php83-xmlwriter` for improved XML handling support
- n8n backup now checks for active workflow executions before stopping service

### Changed
- n8n backup process now waits up to 5 minutes for running workflows to complete before backup
- Backup will be skipped (with error log) if workflows are still active after timeout to avoid interruption

### Fixed
- Prevented n8n hourly backups from interrupting active workflow executions

### Removed
### Security

---


---

## [v1.0.0-dev.8] - 2025-11-07

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.7] - 2025-11-07

> **Commit Summary:** feat: add WordPress user list to startup notification email

### Added
- New `send-startup-email.sh` for container start/restart notifications
- Startup email includes Rspamd credentials and service URLs
- WordPress admin and editor user list in startup email with usernames, emails, and roles
- Graceful handling when WordPress is not yet installed or still initializing

### Changed
- WordPress credentials only sent during initial installation (not on restart)
- Startup notification separates initial credentials from restart notifications

### Fixed
- Startup email now works correctly whether WordPress is fresh or restored from backup
- WordPress password lifecycle properly managed (generated once, stored in WP database, user-managed thereafter)

### Removed
### Security

---


---

## [v1.0.0-dev.6] - 2025-11-07

> **Commit Summary:** fix: enhanced SSL cert renewal with backup and email notification

### Added
- Credentials email now sent on every container startup/restart for visibility and notification
- Email notification when SSL certificates are automatically renewed
- Certificate expiry date included in renewal notification emails

### Changed
- Moved credentials email from WordPress-only setup to end of `setup-full.sh` for all startups
- Added Docker cache prompt to `dev-deploy.sh` workflow
- Enhanced `cert-renew-hook.sh` with proper logging and error handling

### Fixed
- SSL certificate backup path corrected in `cert-renew-hook.sh` (full path to iwb-backup.sh)
### Removed
### Security

---


---

## [v1.0.0-dev.5] - 2025-11-06

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.4] - 2025-11-06

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.3] - 2025-11-06

### Added
### Changed
### Fixed
### Removed
### Security

---


---

## [v1.0.0-dev.2] - 2025-11-06

> **Commit Summary:** feat: automated commit workflow with changelog-driven messages

### Added
- Semantic versioning workflow with `VERSION` file as single source of truth
- Development automation scripts (`dev-deploy.sh`, `bump-version.sh`, `build-and-push.sh`, `release.sh`)
- Interactive commit prompt in `dev-deploy.sh` and `release.sh` for uncommitted changes
- Auto-generated commit messages from CHANGELOG "Commit Summary" section
- Auto-generation and persistence for PostfixAdmin SQL password
- Auto-generation and persistence for Rspamd controller passwords (normal and enable)
- Comprehensive startup credentials email with WordPress, Rspamd, and n8n setup instructions
- First-time setup guidance for n8n in startup email with warning symbols
- Scripts documentation (`scripts/README.md` and `QUICK-REFERENCE.md`)

### Changed
- Reorganized `env.template` into three sections: Required User Input, Optional Configuration, Auto-Generated
- Enhanced password management system to ensure all 5 passwords are auto-generated and persisted to `/var/data/state/`
- Docker tagging strategy: `dev-latest` for development (no version in name), versioned tags for specific builds
- Startup email now includes Rspamd web UI credentials and n8n setup instructions
- `dev-deploy.sh` and `release.sh` now extract commit messages from CHANGELOG instead of prompting
- Workflow now documentation-driven: update CHANGELOG first, commit message auto-generated from it

### Fixed
- PostfixAdmin SQL password now persists correctly across container restarts
- Syntax error in `env.template` (`IWB_PERSISTENT_STORAGE` line cleaned up)
- Password generation lifecycle now consistent for all services (MySQL, PostfixAdmin, WordPress, Rspamd)

### Changed
- Moved to Alpine Linux 3.21 base
- Implemented modular setup script pattern with state flags

### Known Issues
- n8n execution history causes backup bloat (~800MB)
- WordPress Media Cloud plugin fails on 18MB+ zip/tar.gz uploads

---

## Development History (Pre-Changelog)

### Earlier Development
- Initial architecture design
- Docker containerization
- Email stack integration
- WordPress setup automation
- n8n platform integration
