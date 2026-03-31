# Build and Release Scripts

This directory contains scripts for managing versions, building Docker images, and creating releases.

## Changelog-Driven Commit Messages

Our workflow uses the CHANGELOG as the single source of truth for commit messages. When you have uncommitted changes and run `dev-deploy.sh` or `release.sh`, the script automatically extracts the commit message from your CHANGELOG.

**Format:**
```markdown
## [Unreleased]

> **Commit Summary:** feat: your commit message here

### Added
- Feature 1
- Feature 2
```

**Commit message conventions:**
- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `refactor:` - Code refactoring
- `chore:` - Maintenance tasks
- `test:` - Test updates

## Scripts Overview

### `dev-deploy.sh` ⭐ (Primary Development Tool)
**Complete dev deployment in one command** - Use this for daily dev work!

**Usage:**
```bash
./scripts/dev-deploy.sh [OPTIONS]
```

**Options:**
- `--no-cache` - Build Docker without cache
- `--skip-docker` - Skip Docker build/push (git only)
- `--skip-github` - Skip GitHub push (Docker only)
- `--force` - Skip confirmation prompts

**What it does:**
1. Checks you're on dev branch
2. **If uncommitted changes exist:** Prompts to commit them with custom message
3. Bumps version (v1.0.0-dev.1 → v1.0.0-dev.2)
4. Updates CHANGELOG
5. Commits version bump and tags
6. Builds Docker image (tags: versioned + dev-latest)
7. Pushes to Docker Hub
8. Pushes to GitHub (commits + tags)

**Auto-generated commit messages:** If you have uncommitted changes, the script will:
- Show your changed files
- Ask if you want to commit them
- **Automatically extract commit message from CHANGELOG `[Unreleased]` section**
- Show the auto-generated message and ask for confirmation
- Stage and commit all changes before proceeding

**How to use:**
1. Update your CHANGELOG with changes in the `[Unreleased]` section
2. Add a commit summary line: `> **Commit Summary:** feat: your message here`
3. Run `./scripts/dev-deploy.sh` - it will use your summary as the commit message!

**This is your main workflow tool!** Run it when you're done with a work session.

---

### `bump-version.sh`
Increments version and updates CHANGELOG (used by dev-deploy.sh internally).

**Usage:**
```bash
./scripts/bump-version.sh [build|major|minor|patch]
```

**Examples:**
```bash
./scripts/bump-version.sh build    # v1.0.0-dev.1 -> v1.0.0-dev.2
./scripts/bump-version.sh major    # v1.0.0 -> v2.0.0
./scripts/bump-version.sh minor    # v1.0.0 -> v1.1.0
./scripts/bump-version.sh patch    # v1.0.0 -> v1.0.1
```

**What it does:**
1. Reads current version from `VERSION` file
2. Calculates new version based on bump type
3. Updates `VERSION` file
4. Updates `CHANGELOG.md` with new version section
5. Creates git commit and tag

---

### `build-and-push.sh`
Builds Docker image and pushes to Docker Hub.

**Usage:**
```bash
./scripts/build-and-push.sh [OPTIONS]
```

**Options:**
- `--no-cache` - Build without cache (force full rebuild)
- `--skip-push` - Build only, don't push to Docker Hub
- `--platform <platforms>` - Specify platform (e.g., linux/amd64,linux/arm64)
- `--feature-tag <name>` - Build feature-scoped tags for testing (does not update `dev-latest`)

**Examples:**
```bash
./scripts/build-and-push.sh                    # Standard build and push
./scripts/build-and-push.sh --no-cache         # Force rebuild
./scripts/build-and-push.sh --skip-push        # Build only
./scripts/build-and-push.sh --platform linux/amd64,linux/arm64
./scripts/build-and-push.sh --feature-tag dual-storj-r2-migration
```

**What it does:**
1. Reads version from `VERSION` file
2. Determines appropriate Docker tags based on version type:
   - **Dev builds** (`dev-b###`): Tags as `dev-b005` and `dev-latest`
   - **Feature dev builds** (`--feature-tag <name>`): Tags as `feature-<name>-<version>` and `feature-<name>-latest`
   - **Production** (`v#.#.#`): Tags as `v1.0.0`, `1.0.0`, `1.0`, `1`, and `latest`
3. Builds Docker image with all tags
4. Pushes to Docker Hub (`iwbp/iwbdpp`)

---

### `release.sh`
Creates a production release from dev branch.

**Usage:**
```bash
./scripts/release.sh [major|minor|patch]
```

**Examples:**
```bash
./scripts/release.sh patch    # Bug fix release (v1.0.0 -> v1.0.1)
./scripts/release.sh minor    # Feature release (v1.0.0 -> v1.1.0)
./scripts/release.sh major    # Breaking change (v1.0.0 -> v2.0.0)
```

**What it does:**
1. Checks you're on dev branch
2. **If uncommitted changes exist:** Prompts to commit them with custom message
3. Prompts for release type (if not provided)
4. Updates `VERSION` file to semantic version
5. Updates `CHANGELOG.md` with release date
6. Commits changes on dev branch
7. Tags dev branch with `v#.#.#-dev`
8. Merges dev -> main
9. Tags main branch with `v#.#.#`
10. Returns to dev branch
11. Optionally runs `build-and-push.sh`

**Interactive commit workflow:** If you have uncommitted changes, the script will:
- Show your changed files
- Ask if you want to commit them before release
- Prompt for a commit message with examples
- Stage and commit all changes before proceeding

**Prerequisites:**
- Must be on dev branch
- Main branch must exist

---

## Typical Workflows

### Daily Development (dev branch)

**Recommended workflow (changelog-driven commits):**
1. Make your changes (code, configs, etc.)
2. Update `CHANGELOG.md` in the `[Unreleased]` section:
   ```markdown
   ## [Unreleased]
   
   > **Commit Summary:** feat: add email signature feature
   
   ### Added
   - Email signature support in PostfixAdmin
   - New template for signature configuration
   ```
3. Run one command:
   ```bash
   ./scripts/dev-deploy.sh
   ```
4. Script extracts "feat: add email signature feature" and uses it as your commit message
5. Everything else is automatic (version bump, Docker build, push)!

**Manual workflow (if you prefer explicit control):**
1. Make changes and commit:
   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```

2. Bump version:
   ```bash
   ./scripts/bump-version.sh build
   ```

3. Build and push:
   ```bash
   ./scripts/build-and-push.sh
   ```

4. Push to GitHub:
   ```bash
   git push && git push --tags
   ```

### Creating a Release

1. Ensure you're on dev branch with all changes committed

2. Run release script:
   ```bash
   ./scripts/release.sh minor  # or major/patch
   ```

3. Script will pause for you to edit CHANGELOG - add release notes

4. Push everything:
   ```bash
   git push origin dev main --tags
   ```

---

### Version Management

### VERSION File
Located at project root, contains current version following [Semantic Versioning](https://semver.org/):
- Dev: `v1.0.0-dev.1`, `v1.0.0-dev.2`, `v1.1.0-dev.1`, etc.
- Production: `v1.0.0`, `v1.1.0`, `v2.0.0`, etc.

The `-dev.N` suffix indicates pre-release development builds working toward that version.

### CHANGELOG.md
Follows [Keep a Changelog](https://keepachangelog.com/) format.

**Update before releases:**
```markdown
## [Unreleased]

### Added
- New feature descriptions

### Changed
- Modified functionality

### Fixed
- Bug fixes

### Security
- Security improvements
```

Scripts automatically convert `[Unreleased]` to versioned sections.

---

## Docker Tags

### Development Builds (dev branch)
- `iwbp/iwbdpp:dev-latest` - **Always latest dev** (use this for testing!)
- `iwbp/iwbdpp:v1.0.0-dev.5` - Specific build (for rollback)

### Production Releases (main branch)
- `iwbp/iwbdpp:latest` - **Latest stable** (production)
- `iwbp/iwbdpp:v1.0.0` - Full version with 'v'
- `iwbp/iwbdpp:1.0.0` - Full version
- `iwbp/iwbdpp:1.0` - Major.minor
- `iwbp/iwbdpp:1` - Major only

---

## Philosophy

These scripts embody the project's "sovereignty over dependency" principle:
- No external CI/CD services required
- Self-contained bash scripts
- Manual control points for critical operations
- Works anywhere bash and Docker are available

---

## Troubleshooting

### Script won't execute
```bash
chmod +x scripts/*.sh
```

### Git operations fail
- Ensure you have no uncommitted changes
- Check you're on the correct branch
- Verify git remote is configured

### Docker push fails
- Ensure you're logged into Docker Hub: `docker login`
- Check network connectivity
- Verify you have push permissions to `iwbp/iwbdpp`

### Version format errors
- Dev builds must be `v#.#.#-dev.N` format
- Production must be `v#.#.#` format
- Check `VERSION` file for correct format

---

## Complete Workflow Example

Here's a real-world example of the changelog-driven workflow:

**1. Start working on a feature:**
```bash
# Make code changes
vim includes/setup/scripts/send-wp-admin-email.sh
# Add new functionality
```

**2. Document changes in CHANGELOG:**
```bash
vim CHANGELOG.md
```
```markdown
## [Unreleased]

> **Commit Summary:** feat: add Rspamd passwords to startup email

### Added
- Rspamd controller password in startup email
- Rspamd enable password in startup email

### Changed
- Enhanced email template with box-drawing characters
```

**3. Deploy everything with one command:**
```bash
./scripts/dev-deploy.sh
```

**Output:**
```
[DEV-DEPLOY] You have uncommitted changes:
 M includes/setup/scripts/send-wp-admin-email.sh
 M CHANGELOG.md

Commit these changes? [Y/n] y

[INFO] Auto-generated commit message from CHANGELOG:
  feat: add Rspamd passwords to startup email

Use this message? [Y/n] y
[DEV-DEPLOY] Changes committed: feat: add Rspamd passwords to startup email ✓
[DEV-DEPLOY] Version: v1.0.0-dev.1 → v1.0.0-dev.2
[DEV-DEPLOY] Docker build successful ✓
[DEV-DEPLOY] Pushed to Docker Hub ✓
[DEV-DEPLOY] Pushed to GitHub ✓

╔════════════════════════════════════════════════════════╗
║              Deployment Complete! 🚀                   ║
╚════════════════════════════════════════════════════════╝
```

**That's it!** Your changes are committed, versioned, built, and deployed. 🎉

````
