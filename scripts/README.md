# Build and Release Scripts

This directory contains scripts for managing versions, building Docker images, and creating releases.

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
1. Checks you're on dev branch with clean working tree
2. Bumps version (v1.0.0-dev.1 → v1.0.0-dev.2)
3. Updates CHANGELOG
4. Commits and tags
5. Builds Docker image (tags: versioned + dev-latest)
6. Pushes to Docker Hub
7. Pushes to GitHub (commits + tags)

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

**Examples:**
```bash
./scripts/build-and-push.sh                    # Standard build and push
./scripts/build-and-push.sh --no-cache         # Force rebuild
./scripts/build-and-push.sh --skip-push        # Build only
./scripts/build-and-push.sh --platform linux/amd64,linux/arm64
```

**What it does:**
1. Reads version from `VERSION` file
2. Determines appropriate Docker tags based on version type:
   - **Dev builds** (`dev-b###`): Tags as `dev-b005` and `dev-latest`
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
1. Checks you're on dev branch with clean working tree
2. Prompts for release type (if not provided)
3. Updates `VERSION` file to semantic version
4. Updates `CHANGELOG.md` with release date
5. Commits changes on dev branch
6. Tags dev branch with `v#.#.#-dev`
7. Merges dev -> main
8. Tags main branch with `v#.#.#`
9. Returns to dev branch
10. Optionally runs `build-and-push.sh`

**Prerequisites:**
- Must be on dev branch
- No uncommitted changes
- Main branch must exist

---

## Typical Workflows

### Daily Development (dev branch)

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
- Dev builds must be `dev-b###` format
- Production must be `v#.#.#` format
- Check `VERSION` file for correct format
