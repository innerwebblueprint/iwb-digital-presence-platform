#!/usr/bin/env bash
#
# bump-version.sh - Increment version and update CHANGELOG
#
# Usage:
#   ./scripts/bump-version.sh [build|major|minor|patch]
#
# Examples:
#   ./scripts/bump-version.sh build    # dev-b004 -> dev-b005
#   ./scripts/bump-version.sh major    # v1.0.0 -> v2.0.0
#   ./scripts/bump-version.sh minor    # v1.0.0 -> v1.1.0
#   ./scripts/bump-version.sh patch    # v1.0.0 -> v1.0.1

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"
CHANGELOG_FILE="$PROJECT_ROOT/CHANGELOG.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[BUMP]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if VERSION file exists
if [ ! -f "$VERSION_FILE" ]; then
    error "VERSION file not found at $VERSION_FILE"
fi

# Read current version
CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
log "Current version: $CURRENT_VERSION"

# Determine bump type (default to build)
BUMP_TYPE="${1:-build}"

# Calculate new version
case "$BUMP_TYPE" in
    build)
        # Increment build number (dev-b004 -> dev-b005)
        if [[ $CURRENT_VERSION =~ ^dev-b([0-9]+)$ ]]; then
            BUILD_NUM="${BASH_REMATCH[1]}"
            NEW_BUILD_NUM=$((BUILD_NUM + 1))
            NEW_VERSION=$(printf "dev-b%03d" $NEW_BUILD_NUM)
        else
            error "Current version '$CURRENT_VERSION' is not a dev build format (dev-b###)"
        fi
        ;;
    
    major|minor|patch)
        # Semantic version bump
        if [[ $CURRENT_VERSION =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
            MAJOR="${BASH_REMATCH[1]}"
            MINOR="${BASH_REMATCH[2]}"
            PATCH="${BASH_REMATCH[3]}"
            
            case "$BUMP_TYPE" in
                major) NEW_VERSION="v$((MAJOR + 1)).0.0" ;;
                minor) NEW_VERSION="v${MAJOR}.$((MINOR + 1)).0" ;;
                patch) NEW_VERSION="v${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
            esac
        else
            error "Current version '$CURRENT_VERSION' is not semantic versioning format (v#.#.#)"
        fi
        ;;
    
    *)
        error "Unknown bump type: $BUMP_TYPE (use: build, major, minor, or patch)"
        ;;
esac

log "New version: $NEW_VERSION"

# Confirm with user
read -p "$(echo -e ${YELLOW}Bump version from $CURRENT_VERSION to $NEW_VERSION? [y/N]${NC} )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warn "Version bump cancelled"
    exit 0
fi

# Update VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"
log "Updated VERSION file"

# Update CHANGELOG.md
CURRENT_DATE=$(date +%Y-%m-%d)

# Check if CHANGELOG has an [Unreleased] section with content
if grep -q "## \[Unreleased\]" "$CHANGELOG_FILE"; then
    # Create new version entry from Unreleased section
    # Use a temporary file for complex sed operations
    TMP_FILE=$(mktemp)
    
    # Strategy: Insert new version section after [Unreleased], then clear Unreleased content
    awk -v ver="$NEW_VERSION" -v date="$CURRENT_DATE" '
    /^## \[Unreleased\]/ {
        print $0
        print ""
        print "### Added"
        print "### Changed"
        print "### Fixed"
        print "### Removed"
        print "### Security"
        print ""
        print "---"
        print ""
        print "## [" ver "] - " date
        in_unreleased = 1
        next
    }
    /^## \[/ && in_unreleased {
        in_unreleased = 0
        print ""
        print "---"
        print ""
        print $0
        next
    }
    { print }
    ' "$CHANGELOG_FILE" > "$TMP_FILE"
    
    mv "$TMP_FILE" "$CHANGELOG_FILE"
    log "Updated CHANGELOG.md with new version section"
else
    warn "No [Unreleased] section found in CHANGELOG.md - you'll need to update it manually"
fi

# Git operations
log "Staging changes..."
git add "$VERSION_FILE" "$CHANGELOG_FILE"

log "Creating commit..."
git commit -m "chore: bump version to $NEW_VERSION" || warn "Commit failed - you may need to commit manually"

log "Creating git tag..."
git tag -a "$NEW_VERSION" -m "Release $NEW_VERSION" || warn "Tag creation failed - you may need to tag manually"

echo ""
log "Version bump complete!"
log "  Old version: $CURRENT_VERSION"
log "  New version: $NEW_VERSION"
echo ""
log "Next steps:"
log "  1. Review the commit and CHANGELOG.md"
log "  2. Edit CHANGELOG.md to add details about changes"
log "  3. Run: git commit --amend (if you edited CHANGELOG)"
log "  4. Run: ./scripts/build-and-push.sh to build and push Docker image"
log "  5. Run: git push && git push --tags"
