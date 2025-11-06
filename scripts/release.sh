#!/usr/bin/env bash
#
# release.sh - Create a production release from dev branch
#
# Usage:
#   ./scripts/release.sh [major|minor|patch] [OPTIONS]
#
# Options:
#   --force          Skip confirmation prompts
#   --skip-docker    Skip Docker build/push
#   --skip-github    Skip GitHub push
#
# This script:
#   1. Ensures you're on dev branch with clean working tree
#   2. Prompts for release type (major, minor, patch)
#   3. Updates VERSION to semantic version
#   4. Updates CHANGELOG with release notes
#   5. Commits and tags on dev branch (v#.#.#-dev)
#   6. Merges dev -> main
#   7. Tags main branch (v#.#.#)
#   8. Builds Docker with production tags (latest, v#.#.#, #.#.#, #.#, #)
#   9. Pushes to Docker Hub and GitHub
#
# Example:
#   ./scripts/release.sh minor   # Creates v1.1.0 from v1.0.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"
CHANGELOG_FILE="$PROJECT_ROOT/CHANGELOG.md"

# Docker settings
DOCKER_REPO="iwbp/iwbdpp"

# Parse options
RELEASE_TYPE=""
FORCE=false
SKIP_DOCKER=false
SKIP_GITHUB=false

while [[ $# -gt 0 ]]; do
    case $1 in
        major|minor|patch)
            RELEASE_TYPE="$1"
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --skip-github)
            SKIP_GITHUB=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [major|minor|patch] [--force] [--skip-docker] [--skip-github]"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[RELEASE]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

step() {
    echo -e "${CYAN}${BOLD}==>${NC}${BOLD} $1${NC}"
}

# Header
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║          IWB DPP - Production Release                  ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not in a git repository"
fi

# Change to project root
cd "$PROJECT_ROOT"

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)

# Check if we're on dev branch
if [ "$CURRENT_BRANCH" != "dev" ]; then
    error "You must be on the 'dev' branch to create a release (currently on '$CURRENT_BRANCH')"
fi

# Check for uncommitted changes
HAS_CHANGES=false
if ! git diff-index --quiet HEAD --; then
    HAS_CHANGES=true
    warn "You have uncommitted changes:"
    echo ""
    git status --short
    echo ""
    
    if [ "$FORCE" = false ]; then
        read -p "$(echo -e ${YELLOW}Commit these changes before release? [Y/n]${NC} )" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            error "Cannot proceed without committing changes. Please commit or stash them."
        fi
    fi
    
    # Extract commit message from CHANGELOG
    echo ""
    if [ -f "$CHANGELOG_FILE" ]; then
        COMMIT_MSG=$(grep "^> \*\*Commit Summary:\*\*" "$CHANGELOG_FILE" | head -n1 | sed 's/^> \*\*Commit Summary:\*\* //')
        
        if [ -n "$COMMIT_MSG" ]; then
            info "Auto-generated commit message from CHANGELOG:"
            echo -e "  ${CYAN}$COMMIT_MSG${NC}"
            echo ""
            
            if [ "$FORCE" = false ]; then
                read -p "$(echo -e ${YELLOW}Use this message? [Y/n]${NC} )" -n 1 -r
                echo
                if [[ $REPLY =~ ^[Nn]$ ]]; then
                    read -p "$(echo -e ${CYAN}Enter custom commit message:${NC} )" COMMIT_MSG
                fi
            fi
        else
            info "No commit summary found in CHANGELOG. Please enter manually."
            info "Add this to CHANGELOG [Unreleased] section:"
            echo '  > **Commit Summary:** feat: your message here'
            echo ""
            read -p "$(echo -e ${CYAN}Commit message:${NC} )" COMMIT_MSG
        fi
    else
        read -p "$(echo -e ${CYAN}Commit message:${NC} )" COMMIT_MSG
    fi
    
    if [ -z "$COMMIT_MSG" ]; then
        error "Commit message cannot be empty"
    fi
    
    # Add all changes and commit
    git add -A
    git commit -m "$COMMIT_MSG"
    log "Changes committed: $COMMIT_MSG ✓"
    echo ""
fi

# Check if VERSION file exists
if [ ! -f "$VERSION_FILE" ]; then
    error "VERSION file not found at $VERSION_FILE"
fi

# Read current version
CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
log "Current version: $CURRENT_VERSION"

# Determine release type if not provided
if [ -z "$RELEASE_TYPE" ]; then
    echo ""
    echo "Select release type:"
    echo "  1) patch - Bug fixes (v1.0.0 -> v1.0.1)"
    echo "  2) minor - New features (v1.0.0 -> v1.1.0)"
    echo "  3) major - Breaking changes (v1.0.0 -> v2.0.0)"
    echo ""
    read -p "Enter choice [1-3]: " choice
    
    case $choice in
        1) RELEASE_TYPE="patch" ;;
        2) RELEASE_TYPE="minor" ;;
        3) RELEASE_TYPE="major" ;;
        *) error "Invalid choice" ;;
    esac
fi

# Calculate new version from current version or default
if [[ $CURRENT_VERSION =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
elif [[ $CURRENT_VERSION =~ ^dev-b([0-9]+)$ ]]; then
    # If coming from dev build, start at v1.0.0 or ask user
    warn "Current version is a dev build ($CURRENT_VERSION)"
    read -p "Enter starting version (e.g., 1.0.0): " START_VERSION
    if [[ $START_VERSION =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        MAJOR="${BASH_REMATCH[1]}"
        MINOR="${BASH_REMATCH[2]}"
        PATCH="${BASH_REMATCH[3]}"
    else
        error "Invalid version format. Use #.#.# format"
    fi
else
    error "Unknown version format: $CURRENT_VERSION"
fi

# Calculate new version
case "$RELEASE_TYPE" in
    major) NEW_VERSION="v$((MAJOR + 1)).0.0" ;;
    minor) NEW_VERSION="v${MAJOR}.$((MINOR + 1)).0" ;;
    patch) NEW_VERSION="v${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
    *) error "Invalid release type: $RELEASE_TYPE (use major, minor, or patch)" ;;
esac

log "New release version: $NEW_VERSION"
echo ""

# Display summary
info "Release Summary:"
echo "  Current version: $CURRENT_VERSION"
echo "  New version:     $NEW_VERSION"
echo "  Release type:    $RELEASE_TYPE"
echo "  Current branch:  $CURRENT_BRANCH"
echo ""

# Confirm with user
if [ "$FORCE" = false ]; then
    read -p "$(echo -e ${YELLOW}Proceed with release? [y/N]${NC} )" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Release cancelled"
        exit 0
    fi
fi

# Step 1: Update VERSION file
log "Updating VERSION file to $NEW_VERSION..."
echo "$NEW_VERSION" > "$VERSION_FILE"

# Step 2: Update CHANGELOG
log "Updating CHANGELOG.md..."
CURRENT_DATE=$(date +%Y-%m-%d)

if grep -q "## \[Unreleased\]" "$CHANGELOG_FILE"; then
    TMP_FILE=$(mktemp)
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
fi

info "Please edit CHANGELOG.md to add release notes for $NEW_VERSION"
if [ "$FORCE" = false ]; then
    read -p "Press Enter when ready to continue..." 
fi

# Step 3: Commit on dev branch
step "Step 3: Committing Changes on Dev Branch"
git add "$VERSION_FILE" "$CHANGELOG_FILE"
git commit -m "chore: release $NEW_VERSION"
git tag -a "$NEW_VERSION-dev" -m "Development release $NEW_VERSION"
log "Committed and tagged dev branch ✓"

# Step 4: Merge to main
step "Step 4: Merging to Main Branch"
git checkout main || error "Failed to checkout main branch"
git merge dev -m "chore: merge dev for release $NEW_VERSION" || error "Merge failed"
git tag -a "$NEW_VERSION" -m "Release $NEW_VERSION"
log "Merged to main and tagged ✓"

# Step 5: Build Docker images (on main branch)
if [ "$SKIP_DOCKER" = false ]; then
    step "Step 5: Building Docker Images"
    
    if [ ! -f "$PROJECT_ROOT/Dockerfile" ]; then
        error "Dockerfile not found in $PROJECT_ROOT"
    fi
    
    # Extract version numbers for tags
    if [[ $NEW_VERSION =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        MAJOR="${BASH_REMATCH[1]}"
        MINOR="${BASH_REMATCH[2]}"
        PATCH="${BASH_REMATCH[3]}"
        
        info "Building with production tags:"
        echo "  - $DOCKER_REPO:$NEW_VERSION"
        echo "  - $DOCKER_REPO:$MAJOR.$MINOR.$PATCH"
        echo "  - $DOCKER_REPO:$MAJOR.$MINOR"
        echo "  - $DOCKER_REPO:$MAJOR"
        echo "  - $DOCKER_REPO:latest"
        echo ""
        
        docker build \
            -t "$DOCKER_REPO:$NEW_VERSION" \
            -t "$DOCKER_REPO:$MAJOR.$MINOR.$PATCH" \
            -t "$DOCKER_REPO:$MAJOR.$MINOR" \
            -t "$DOCKER_REPO:$MAJOR" \
            -t "$DOCKER_REPO:latest" \
            . || error "Docker build failed"
        
        log "Docker build successful ✓"
        
        # Push to Docker Hub
        step "Step 6: Pushing to Docker Hub"
        
        docker push "$DOCKER_REPO:$NEW_VERSION" || error "Failed to push $NEW_VERSION"
        docker push "$DOCKER_REPO:$MAJOR.$MINOR.$PATCH" || error "Failed to push $MAJOR.$MINOR.$PATCH"
        docker push "$DOCKER_REPO:$MAJOR.$MINOR" || error "Failed to push $MAJOR.$MINOR"
        docker push "$DOCKER_REPO:$MAJOR" || error "Failed to push $MAJOR"
        docker push "$DOCKER_REPO:latest" || error "Failed to push latest"
        
        log "Pushed to Docker Hub ✓"
    fi
else
    warn "Skipping Docker build/push (--skip-docker flag)"
fi

# Step 7: Return to dev branch
git checkout dev

# Step 8: Push to GitHub
if [ "$SKIP_GITHUB" = false ]; then
    STEP_NUM=$([ "$SKIP_DOCKER" = false ] && echo "7" || echo "5")
    step "Step $STEP_NUM: Pushing to GitHub"
    
    if [ "$FORCE" = false ]; then
        read -p "$(echo -e ${YELLOW}Push to GitHub (both branches + tags)? [Y/n]${NC} )" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            warn "GitHub push cancelled"
            git checkout dev
            exit 0
        fi
    fi
    
    git push origin dev main || error "Failed to push branches"
    git push origin --tags || warn "Failed to push tags (may already exist)"
    
    log "Pushed to GitHub ✓"
else
    warn "Skipping GitHub push (--skip-github flag)"
fi

# Success summary
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║           Production Release Complete! 🎉             ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Release version: ${BOLD}$NEW_VERSION${NC}"
echo ""

info "Git branches and tags:"
echo "  - dev branch: tagged as $NEW_VERSION-dev"
echo "  - main branch: tagged as $NEW_VERSION"
echo ""

if [ "$SKIP_DOCKER" = false ]; then
    info "Docker images available:"
    echo "  - $DOCKER_REPO:latest (production)"
    echo "  - $DOCKER_REPO:$NEW_VERSION"
    echo "  - $DOCKER_REPO:$MAJOR.$MINOR.$PATCH"
    echo "  - $DOCKER_REPO:$MAJOR.$MINOR"
    echo "  - $DOCKER_REPO:$MAJOR"
    echo ""
fi

info "Quick reference:"
echo "  - Latest dev: docker pull $DOCKER_REPO:dev-latest"
echo "  - Latest production: docker pull $DOCKER_REPO:latest"
echo ""
