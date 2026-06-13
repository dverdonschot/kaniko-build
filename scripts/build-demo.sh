#!/usr/bin/env bash
# build-demo.sh — build the demo-alpine-uv container using the published
# kaniko executor. Writes a plain Docker-compatible tarball to the host
# (no registry push).
#
# Usage:
#   ./scripts/build-demo.sh [--context <dir>] [--dockerfile <path>]
#                          [--kaniko-image <ref>] [--output <dir>]
#                          [--tag <string>] [--no-kaniko]
#
# Defaults:
#   --context        examples/demo-alpine-uv   (resolved relative to repo root)
#   --dockerfile     Dockerfile.demo
#   --kaniko-image   ghcr.io/dverdonschot/executor:v0.1.0-fork1
#   --output         /tmp/demo-oci
#   --tag            dev
#   --no-kaniko      off
#
# Examples:
#   ./scripts/build-demo.sh
#   ./scripts/build-demo.sh --no-kaniko
#   ./scripts/build-demo.sh --output $HOME/demo-oci --tag test1
#   ./scripts/build-demo.sh --kaniko-image ghcr.io/me/executor:latest
#
# Requires: docker with buildx, the kaniko image (or buildx for --no-kaniko),
# a writable output directory on the host.

set -euo pipefail

# Locate the repo root from this script's path, so the script works no
# matter where it's invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONTEXT="examples/demo-alpine-uv"
DOCKERFILE="Dockerfile.demo"
KANIKO_IMAGE="ghcr.io/dverdonschot/executor:v0.1.0-fork1"
OUTPUT="/tmp/demo-oci"
TAG="dev"
NO_KANIKO=false

usage() {
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

log() { printf '\033[1;34m[build-demo]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[build-demo]\033[0m %s\n' "$*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required tool: $1"; exit 1; }
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)        CONTEXT="$2"; shift 2;;
    --dockerfile)     DOCKERFILE="$2"; shift 2;;
    --kaniko-image)   KANIKO_IMAGE="$2"; shift 2;;
    --output)         OUTPUT="$2"; shift 2;;
    --tag)            TAG="$2"; shift 2;;
    --no-kaniko)      NO_KANIKO=true; shift;;
    -h|--help)        usage 0;;
    *) err "unknown arg: $1"; usage 1;;
  esac
done

# Resolve context to an absolute path; kaniko and buildx both prefer this.
if [[ "${CONTEXT}" = /* ]]; then
  CONTEXT_ABS="${CONTEXT}"
else
  CONTEXT_ABS="${REPO_ROOT}/${CONTEXT}"
fi
DOCKERFILE_PATH="${CONTEXT_ABS}/${DOCKERFILE}"

require docker
docker buildx version >/dev/null 2>&1 || { err "docker buildx not available"; exit 1; }

[[ -d "${CONTEXT_ABS}" ]]    || { err "--context '${CONTEXT_ABS}' is not a directory"; exit 1; }
[[ -f "${DOCKERFILE_PATH}" ]] || { err "--dockerfile '${DOCKERFILE_PATH}' does not exist"; exit 1; }

# Warn (don't fail) if the output is outside $HOME; rootless dockerd
# typically refuses bind mounts from outside the user's home.
if [[ -n "${HOME:-}" && "${OUTPUT}" != "${HOME}"/* && "${OUTPUT}" != /tmp/* ]]; then
  err "warning: --output '${OUTPUT}' is outside \$HOME and not /tmp; rootless dockerd may refuse the bind mount"
fi

# Make sure the output dir exists and is writable. We always write to a
# tarball at <output>/demo-alpine-uv-<tag>.tar.
mkdir -p "${OUTPUT}"
TARBALL_PATH="${OUTPUT}/demo-alpine-uv-${TAG}.tar"
LOAD_TAG="demo-alpine-uv:${TAG}"

log "context       : ${CONTEXT_ABS}"
log "dockerfile    : ${DOCKERFILE_PATH}"
log "kaniko-image  : ${KANIKO_IMAGE}"
log "output dir    : ${OUTPUT}"
log "tarball       : ${TARBALL_PATH}"
log "image tag     : ${LOAD_TAG}"
log "no-kaniko     : ${NO_KANIKO}"

if [[ "${NO_KANIKO}" == true ]]; then
  log "fallback path: using docker buildx build (not kaniko)"
  # `type=docker` (NOT `type=tar`) produces a `docker save`-compatible
  # tarball with a top-level `manifest.json`, which `docker load -i`
  # can consume directly. The plain `type=tar` (rootfs) variant is
  # rejected by `docker load` as "unrecognized image format".
  docker buildx build \
    --tag "${LOAD_TAG}" \
    --output "type=docker,dest=${TARBALL_PATH}" \
    --file "${DOCKERFILE_PATH}" \
    "${CONTEXT_ABS}"
  log "done. load with: docker load -i ${TARBALL_PATH}"
  exit 0
fi

# Sanity-check the published kaniko image is reachable. This catches a
# typo in --kaniko-image before we burn time on a doomed build.
if ! docker image inspect "${KANIKO_IMAGE}" >/dev/null 2>&1; then
  log "kaniko image not present locally; pulling ${KANIKO_IMAGE}"
  docker pull "${KANIKO_IMAGE}"
fi

log "running kaniko executor in a container"
# We bind-mount:
#   * the build context at /workspace
#   * the output dir at /output, where kaniko will write the tarball
#
# kaniko flags:
#   --context=/workspace               build from the local directory
#   --dockerfile=/workspace/<Dockerfile>
#   --destination=tar:/output/...      write a Docker-compatible tarball
#   --no-push                          explicit: we are not pushing
#   --cache=true                       use the default cache (local FS)
#   --cache-dir=/cache                 writable cache dir
#
# Notes on rootless Docker:
#   * The published kaniko image runs as a non-root user internally
#     (scratch-based, see sibling plan's ADR-0001). The `--user 0:0`
#     override lets it write to the bind-mounted output dir owned by
#     the host user, which is the most common rootless setup.
#   * If that fails on the actual Silverblue box, the runbook's
#     "Troubleshooting" section has the next things to try.
docker run --rm \
  --user 0:0 \
  -v "${CONTEXT_ABS}:/workspace" \
  -v "${OUTPUT}:/output" \
  "${KANIKO_IMAGE}" \
  --context=/workspace \
  --dockerfile="/workspace/${DOCKERFILE}" \
  --destination="tar:/output/demo-alpine-uv-${TAG}.tar" \
  --no-push \
  --cache=true \
  --cache-dir=/cache

if [[ ! -s "${TARBALL_PATH}" ]]; then
  err "kaniko exited cleanly but ${TARBALL_PATH} is missing or empty"
  exit 1
fi

log "done. load with: docker load -i ${TARBALL_PATH}"
log "verify with:    ./scripts/verify-demo.sh --image ${TARBALL_PATH}"
