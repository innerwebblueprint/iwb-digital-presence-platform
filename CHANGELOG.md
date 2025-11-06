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
- Working email support with Postfix/Dovecot/Rspamd
- State-based setup script architecture for idempotent deployments
- Storj cloud backup integration for all persistent data
- PostfixAdmin for email account management
- Automated SSL certificate management via certbot
- WordPress integration with persistent storage
- n8n automation platform with security isolation
- Akash Network wallet management (creation/restore)
- Comprehensive backup/restore system with dataset support
- Cron-based automated backups (hourly, daily, weekly, monthly, yearly)

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

