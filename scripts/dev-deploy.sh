#!/usr/bin/env bash
#
# dev-deploy.sh - Complete dev deployment in one command
#
# Usage:
#   ./scripts/dev-deploy.sh [OPTIONS]
#
# This script does EVERYTHING for a dev deployment:
#   1. Ensures working directory is clean (all changes committed)
#   2. Bumps dev version (v1.0.0-dev.4 -> v1.0.0-dev.5)
#   3. Updates CHANGELOG
#   4. Commits version bump
#   5. Creates git tag
#   6. Builds Docker image with dev-latest and version tags
#   7. Pushes to Docker Hub
#   8. Pushes to GitHub (commits + tags)
#
# Options:
#   --no-cache       Build Docker without cache
#   --skip-docker    Skip Docker build/push (git only)
#   --skip-github    Skip GitHub push (Docker only)
#   --force          Skip confirmation prompts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"
CHANGELOG_FILE="$PROJECT_ROOT/CHANGELOG.md"

# Docker settings
DOCKER_REPO="iwbp/iwbdpp"

# Parse options
NO_CACHE=""
SKIP_DOCKER=false
SKIP_GITHUB=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cache)
            NO_CACHE="--no-cache"
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
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--no-cache] [--skip-docker] [--skip-github] [--force]"
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
    echo -e "${GREEN}[DEV-DEPLOY]${NC} $1"
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

# Change to project root
cd "$PROJECT_ROOT"

# Header
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         IWB DPP - Development Deployment               ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check git repository
step "Step 1: Checking Git Repository"

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not in a git repository"
fi

CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "dev" ]; then
    error "You must be on 'dev' branch (currently on '$CURRENT_BRANCH')"
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
        read -p "$(echo -e ${YELLOW}Commit these changes? [Y/n]${NC} )" -n 1 -r
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

log "On dev branch with clean working tree ✓"

# Step 2: Bump version
step "Step 2: Bumping Version"

if [ ! -f "$VERSION_FILE" ]; then
    error "VERSION file not found at $VERSION_FILE"
fi

CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

# Parse version: v1.0.0-dev.1 -> v1.0.0-dev.2
if [[ $CURRENT_VERSION =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)-dev\.([0-9]+)$ ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    DEV_NUM="${BASH_REMATCH[4]}"
    NEW_DEV_NUM=$((DEV_NUM + 1))
    NEW_VERSION="v${MAJOR}.${MINOR}.${PATCH}-dev.${NEW_DEV_NUM}"
elif [[ $CURRENT_VERSION =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    # Coming from a release version, start new dev cycle
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    # Assume next patch version for dev
    NEW_VERSION="v${MAJOR}.${MINOR}.$((PATCH + 1))-dev.1"
    warn "Starting new dev cycle from release version"
else
    error "Current version '$CURRENT_VERSION' is not valid format (expected v#.#.#-dev.# or v#.#.#)"
fi

log "Version: $CURRENT_VERSION → $NEW_VERSION"

# Update VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"

# Update CHANGELOG
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

# Git commit and tag
git add "$VERSION_FILE" "$CHANGELOG_FILE"
git commit -m "chore: bump version to $NEW_VERSION"
git tag -a "$NEW_VERSION" -m "Development build $NEW_VERSION"

log "Created commit and tag for $NEW_VERSION ✓"

# Step 3: Build Docker image
if [ "$SKIP_DOCKER" = false ]; then
    step "Step 3: Building Docker Image"

    # Ask about cache unless --no-cache flag was set or --force is used
    if [ -z "$NO_CACHE" ] && [ "$FORCE" = false ]; then
        read -p "$(echo -e ${YELLOW}'Use Docker cache? [Y/n]'${NC} )" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            NO_CACHE="--no-cache"
            info "Building without cache (full rebuild)"
        else
            info "Building with cache (faster)"
        fi
        echo ""
    fi
    
    if [ "$FORCE" = false ]; then
        read -p "$(echo -e ${YELLOW}'Proceed with Docker build? [Y/n]'${NC} )" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            warn "Docker build cancelled"
            exit 0
        fi
    fi

    BUILD_CMD=("$PROJECT_ROOT/scripts/build-and-push.sh" "--yes")
    if [ -n "$NO_CACHE" ]; then
        BUILD_CMD+=("--no-cache")
    fi

    "${BUILD_CMD[@]}" || error "Docker build/push failed"

    log "Docker build and push successful ✓"
else
    warn "Skipping Docker build/push (--skip-docker flag)"
fi

# Step 5: Push to GitHub
if [ "$SKIP_GITHUB" = false ]; then
    step "Step 5: Pushing to GitHub"
    
    if [ "$FORCE" = false ]; then
        read -p "$(echo -e ${YELLOW}'Push to GitHub (commits + tags)? [Y/n]'${NC} )" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            warn "GitHub push cancelled"
            exit 0
        fi
    fi
    
    git push origin dev || error "Failed to push commits to GitHub"
    git push origin --tags || warn "Failed to push tags (may already exist)"
    
    log "Pushed to GitHub ✓"
else
    warn "Skipping GitHub push (--skip-github flag)"
fi

# Success summary
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              Deployment Complete!                      ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Version deployed: ${BOLD}$NEW_VERSION${NC}"
echo ""

if [ "$SKIP_DOCKER" = false ]; then
    info "Docker images available:"
    echo "  - $DOCKER_REPO:$NEW_VERSION"
    echo "  - $DOCKER_REPO:dev-latest"
    echo ""
fi

if [ "$SKIP_GITHUB" = false ]; then
    info "GitHub updated:"
    echo "  - Branch: dev"
    echo "  - Tag: $NEW_VERSION"
    echo ""
fi

info "Next steps:"
echo "  - Test the deployment: docker pull $DOCKER_REPO:dev-latest"
echo "  - When ready for release: ./scripts/release.sh [major|minor|patch]"
echo ""
