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

