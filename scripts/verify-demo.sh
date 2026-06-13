#!/usr/bin/env bash
# verify-demo.sh — load the tarball produced by build-demo.sh into the
# local Docker daemon, run the container, and assert that uv + python
# both work end-to-end.
#
# Usage:
#   ./scripts/verify-demo.sh [--image <tarball>] [--tag <string>]
#
# Defaults:
#   --image   /tmp/demo-oci/demo-alpine-uv-dev.tar
#   --tag     dev
#
# Examples:
#   ./scripts/verify-demo.sh
#   ./scripts/verify-demo.sh --image $HOME/demo-oci/demo-alpine-uv-test1.tar --tag test1
#
# Asserts:
#   1. docker load -i <tarball> succeeds
#   2. docker run --rm <image> uv --version exits 0
#   3. docker run --rm <image> python --version exits 0
#   4. docker run --rm <image> uv run python -c 'print(1+1)' prints 2
#
# Requires: docker CLI, a loaded demo-alpine-uv:<tag> image.

set -euo pipefail

IMAGE="/tmp/demo-oci/demo-alpine-uv-dev.tar"
TAG="dev"
LOAD_TAG="demo-alpine-uv:${TAG}"

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

log() { printf '\033[1;34m[verify-demo]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[verify-demo]\033[0m %s\n' "$*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required tool: $1"; exit 1; }
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2;;
    --tag)   TAG="$2"; shift 2;;
    -h|--help) usage 0;;
    *) err "unknown arg: $1"; usage 1;;
  esac
done

# Derive LOAD_TAG from --tag (the tarball filename also encodes the tag,
# but the user may have renamed the tarball).
LOAD_TAG="demo-alpine-uv:${TAG}"

require docker

[[ -s "${IMAGE}" ]] || { err "--image '${IMAGE}' does not exist or is empty"; exit 1; }

log "image tarball : ${IMAGE}"
log "load as       : ${LOAD_TAG}"

log "loading tarball into dockerd"
docker load -i "${IMAGE}"

# Sanity: the image should now be present.
if ! docker image inspect "${LOAD_TAG}" >/dev/null 2>&1; then
  err "tarball loaded but '${LOAD_TAG}' is not present in the local daemon"
  err "inspect with:  docker images"
  exit 1
fi

# Each check is a separate `docker run --rm` so a failure in one doesn't
# mask the others' output. We capture stdout/stderr so the user can see
# what the container actually printed.

check_uv_version() {
  log "check 1/3: uv --version"
  local out
  if ! out="$(docker run --rm "${LOAD_TAG}" --version 2>&1)"; then
    err "uv --version failed"
    printf '%s\n' "${out}" >&2
    return 1
  fi
  printf '  %s\n' "${out}"
}

check_python_version() {
  log "check 2/3: python --version (via uv run)"
  # The Dockerfile's ENTRYPOINT is `uv`, so a bare `python --version`
  # gets parsed as `uv python --version` which fails: uv's `python`
  # subcommand manages interpreters, and `--version` looks like a
  # subcommand name. Run it through `uv run` to actually invoke the
  # installed Python interpreter.
  local out
  if ! out="$(docker run --rm "${LOAD_TAG}" run python --version 2>&1)"; then
    err "uv run python --version failed"
    printf '%s\n' "${out}" >&2
    return 1
  fi
  printf '  %s\n' "${out}"
}

check_uv_run_python() {
  log 'check 3/3: uv run python -c "print(1+1)"'
  local out
  if ! out="$(docker run --rm "${LOAD_TAG}" run python -c 'print(1+1)' 2>&1)"; then
    err "uv run python -c 'print(1+1)' failed"
    printf '%s\n' "${out}" >&2
    return 1
  fi
  if [[ "${out}" != "2" ]]; then
    err "expected '2' from uv run python, got: ${out}"
    return 1
  fi
  printf '  %s\n' "${out}"
}

# Run all three checks. If any fails, exit non-zero.
failed=0
check_uv_version     || failed=1
check_python_version || failed=1
check_uv_run_python  || failed=1

if [[ "${failed}" -ne 0 ]]; then
  err "one or more checks failed"
  exit 1
fi

log "all checks passed"
