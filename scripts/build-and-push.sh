#!/usr/bin/env bash
#
# build-and-push.sh - Build Docker image and push to Docker Hub
#
# Usage:
#   ./scripts/build-and-push.sh [OPTIONS]
#
# Options:
#   --no-cache    Build without cache
#   --skip-push   Build only, don't push to Docker Hub
#   --feature-tag Build feature-scoped tags (e.g., dual-storj-r2-migration)
#   --yes         Skip push confirmation prompt
#
# This script:
#   1. Reads version from VERSION file
#   2. Builds Docker image with multiple tags
#   3. Pushes to Docker Hub (iwbp/iwbdpp)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"

# Docker image settings
DOCKER_REPO="iwbp/iwbdpp"

# Parse options
NO_CACHE=""
SKIP_PUSH=false
FEATURE_TAG=""
ASSUME_YES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --skip-push)
            SKIP_PUSH=true
            shift
            ;;
        --feature-tag)
            FEATURE_TAG="$2"
            shift 2
            ;;
        --yes)
            ASSUME_YES=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[BUILD]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

resolve_latest_n8n_version() {
    local dist_tags
    local latest

    dist_tags=$(curl -fsSL "https://registry.npmjs.org/-/package/n8n/dist-tags") || return 1
    latest=$(printf '%s' "$dist_tags" | sed -n 's/.*"latest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -z "$latest" ]; then
        return 1
    fi

    printf '%s\n' "$latest"
}

resolve_n8n_node_major() {
    local n8n_version="$1"
    local package_json
    local node_engine
    local node_major

    package_json=$(curl -fsSL "https://registry.npmjs.org/n8n/${n8n_version}") || return 1
    node_engine=$(printf '%s' "$package_json" | sed -n 's/.*"node"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -z "$node_engine" ]; then
        return 1
    fi

    node_major=$(printf '%s' "$node_engine" | sed -n 's/.*>=\([0-9][0-9]*\).*/\1/p')

    if [ -z "$node_major" ]; then
        return 1
    fi

    printf '%s\n' "$node_major"
}

# Check if VERSION file exists
if [ ! -f "$VERSION_FILE" ]; then
    error "VERSION file not found at $VERSION_FILE"
fi

# Read current version
VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
log "Building version: $VERSION"

sanitize_feature_tag() {
    local raw="$1"
    local sanitized
    sanitized=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/--+/-/g')
    echo "$sanitized"
}

FEATURE_TAG_SANITIZED=""
if [ -n "$FEATURE_TAG" ]; then
    FEATURE_TAG_SANITIZED=$(sanitize_feature_tag "$FEATURE_TAG")
    if [ -z "$FEATURE_TAG_SANITIZED" ]; then
        error "Invalid --feature-tag value after sanitization: '$FEATURE_TAG'"
    fi
    info "Feature tag mode enabled: $FEATURE_TAG_SANITIZED"
fi

# Determine tags based on version type
TAGS=()
CURRENT_BRANCH="$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || true)"

if [[ $VERSION =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)-dev\.([0-9]+)$ ]]; then
    # Development build (semver format: v1.0.0-dev.11)
    if [ -n "$FEATURE_TAG_SANITIZED" ]; then
        TAGS+=("-t" "$DOCKER_REPO:feature-${FEATURE_TAG_SANITIZED}-${VERSION}")
        TAGS+=("-t" "$DOCKER_REPO:feature-${FEATURE_TAG_SANITIZED}-latest")
        log "Feature development build detected (semver dev)"
    else
        TAGS+=("-t" "$DOCKER_REPO:$VERSION")
        TAGS+=("-t" "$DOCKER_REPO:dev-latest")
        log "Development build detected (semver dev)"
    fi

elif [[ $VERSION =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    # Production release
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    
    TAGS+=("-t" "$DOCKER_REPO:$VERSION")
    TAGS+=("-t" "$DOCKER_REPO:$MAJOR.$MINOR.$PATCH")
    TAGS+=("-t" "$DOCKER_REPO:$MAJOR.$MINOR")
    TAGS+=("-t" "$DOCKER_REPO:$MAJOR")
    TAGS+=("-t" "$DOCKER_REPO:latest")
    log "Production release detected"

else
    error "Unknown version format: $VERSION (expected v#.#.#-dev.# or v#.#.#)"
fi

if [[ "$VERSION" =~ -dev\. ]] && [ -z "$FEATURE_TAG_SANITIZED" ] && [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "dev" ] && [ "$CURRENT_BRANCH" != "main" ]; then
    info "Current branch is '$CURRENT_BRANCH'. Building without --feature-tag will publish/update dev tags."
fi

# Display tags
info "Docker tags to be created:"
for tag in "${TAGS[@]}"; do
    if [[ $tag != "-t" ]]; then
        echo "  - $tag"
    fi
done
echo ""

# Check if we're in the project root
if [ ! -f "$PROJECT_ROOT/Dockerfile" ]; then
    error "Dockerfile not found in $PROJECT_ROOT"
fi

# Change to project root
cd "$PROJECT_ROOT"

# Resolve latest stable n8n once so the Docker layer only invalidates when the version changes.
N8N_VERSION=$(resolve_latest_n8n_version) || error "Failed to resolve latest stable n8n version from npm registry"
info "Resolved n8n latest stable version: $N8N_VERSION"
NODE_MAJOR=$(resolve_n8n_node_major "$N8N_VERSION") || error "Failed to resolve required Node.js major version for n8n@$N8N_VERSION"
info "Resolved Node.js major version for n8n@$N8N_VERSION: $NODE_MAJOR"

# Always bust cache for iwb-akash-deploy fetch layer
AKASH_DEPLOY_CACHE_BUST=$(date +%s)
info "IWB_AKASH_DEPLOY_CACHE_BUST=$AKASH_DEPLOY_CACHE_BUST"

# Build the image
log "Building Docker image..."
info "Command: docker build $NO_CACHE --build-arg NODE_MAJOR=$NODE_MAJOR --build-arg N8N_VERSION=$N8N_VERSION --build-arg IWB_AKASH_DEPLOY_CACHE_BUST=$AKASH_DEPLOY_CACHE_BUST ${TAGS[*]} ."
echo ""

docker build $NO_CACHE \
    --build-arg "NODE_MAJOR=$NODE_MAJOR" \
    --build-arg "N8N_VERSION=$N8N_VERSION" \
    --build-arg "IWB_AKASH_DEPLOY_CACHE_BUST=$AKASH_DEPLOY_CACHE_BUST" \
    "${TAGS[@]}" . || error "Docker build failed"

log "Docker build successful!"
echo ""

# Push to Docker Hub (unless --skip-push)
if [ "$SKIP_PUSH" = true ]; then
    log "Skipping push to Docker Hub (--skip-push flag set)"
    exit 0
fi

# Confirm push
if [ "$ASSUME_YES" = false ]; then
    read -p "$(echo -e ${YELLOW}Push images to Docker Hub? [y/N]${NC} )" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Push cancelled"
        exit 0
    fi
fi

log "Pushing images to Docker Hub..."
echo ""

# Push all tags
for tag in "${TAGS[@]}"; do
    if [[ $tag != "-t" ]]; then
        log "Pushing $tag..."
        docker push "$tag" || error "Failed to push $tag"
    fi
done

echo ""
log "All images pushed successfully!"
log "Version $VERSION is now available on Docker Hub"
echo ""
info "Available tags:"
for tag in "${TAGS[@]}"; do
    if [[ $tag != "-t" ]]; then
        echo "  - $tag"
    fi
done
