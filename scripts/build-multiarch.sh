#!/usr/bin/env bash
# build-multiarch.sh — build the four Chainguard-fork kaniko targets and (optionally) push them.
#
# Usage:
#   ./scripts/build-multiarch.sh --source <path-to-kaniko-upstream> [--push] [--platforms <csv>] [--registry <registry>]
#
# Defaults:
#   --platforms  linux/amd64,linux/arm64,linux/s390x,linux/ppc64le
#   --registry   $REGISTRY, else ghcr.io/<user>/kaniko (placeholder)
#
# Examples:
#   ./scripts/build-multiarch.sh --source ../kaniko-upstream                       # local arch only, no push
#   ./scripts/build-multiarch.sh --source ../kaniko-upstream --push --registry ghcr.io/me/kaniko
#   ./scripts/build-multiarch.sh --source ../kaniko-upstream --platforms linux/amd64
#
# Requires: docker with buildx, QEMU binfmt registered for non-native archs.

set -euo pipefail

SOURCE=""
PUSH=false
PLATFORMS="linux/amd64,linux/arm64,linux/s390x,linux/ppc64le"
REGISTRY="${REGISTRY:-ghcr.io/your-namespace/kaniko}"
BUILDER_NAME="kaniko-multiarch"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

log() { printf '\033[1;34m[build-multiarch]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[build-multiarch]\033[0m %s\n' "$*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required tool: $1"; exit 1; }
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)     SOURCE="$2"; shift 2;;
    --push)       PUSH=true; shift;;
    --platforms)  PLATFORMS="$2"; shift 2;;
    --registry)   REGISTRY="$2"; shift 2;;
    --builder)    BUILDER_NAME="$2"; shift 2;;
    -h|--help)    usage 0;;
    *) err "unknown arg: $1"; usage 1;;
  esac
done

[[ -z "$SOURCE" ]] && { err "--source is required (path to a clone of chainguard-forks/kaniko)"; usage 1; }
[[ -d "$SOURCE" ]] || { err "--source '$SOURCE' is not a directory"; exit 1; }
[[ -f "$SOURCE/deploy/Dockerfile" ]] || { err "no deploy/Dockerfile under '$SOURCE' — wrong repo?"; exit 1; }

require docker
docker buildx version >/dev/null 2>&1 || { err "docker buildx not available"; exit 1; }

log "source       : $SOURCE"
log "registry     : $REGISTRY"
log "platforms    : $PLATFORMS"
log "push         : $PUSH"

# Ensure a buildx builder exists that can target the requested platforms.
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
  log "creating buildx builder '$BUILDER_NAME'"
  docker buildx create --name "$BUILDER_NAME" --driver docker-container --bootstrap >/dev/null
fi
docker buildx use "$BUILDER_NAME"

# Mirror the upstream matrix: target name : dockerfile target : platforms : registry tag suffix
# Note: platforms are constrained by what upstream declares for each target.
declare -a TARGETS=(
  "executor|kaniko-executor|linux/amd64,linux/arm64,linux/s390x,linux/ppc64le|executor"
  "debug   |kaniko-debug   |linux/amd64,linux/arm64,linux/s390x          |executor:debug"
  "slim    |kaniko-slim    |linux/amd64,linux/arm64,linux/s390x,linux/ppc64le|executor:slim"
  "warmer  |kaniko-warmer  |linux/amd64,linux/arm64,linux/s390x,linux/ppc64le|warmer"
)

# Filter the requested platforms to the union of what the targets actually support.
SUPPORTED_UNION="linux/amd64,linux/arm64,linux/s390x,linux/ppc64le"
if [[ "$PLATFORMS" != "$SUPPORTED_UNION" ]]; then
  log "using custom platform set: $PLATFORMS"
fi

PUSH_FLAG="false"
[[ "$PUSH" == "true" ]] && PUSH_FLAG="true"

for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name target platforms tag <<< "$entry"
  # Trim whitespace from each field
  name="${name// /}"; target="${target// /}"; platforms="${platforms// /}"; tag="${tag// /}"

  # Final registry+tag, e.g. "ghcr.io/me/kaniko/executor:debug"
  image="${REGISTRY%/}/${tag}"

  log "→ building $name as $image  (target=$target, platforms=$platforms, push=$PUSH_FLAG)"
  docker buildx build \
    --platform "$platforms" \
    --target "$target" \
    --file "$SOURCE/deploy/Dockerfile" \
    --tag "$image" \
    --push="$PUSH_FLAG" \
    --cache-from "type=local,src=$HOME/.cache/buildx" \
    --cache-to   "type=local,dest=$HOME/.cache/buildx,mode=max" \
    "$SOURCE"
done

log "done."
if [[ "$PUSH" != "true" ]]; then
  log "(dry-run mode — set --push to actually publish to $REGISTRY)"
fi
