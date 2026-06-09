# Kaniko Build (Chainguard fork, self-hosted)

Build, sign, and publish a hardened `scratch`-based kaniko image (executor / debug / slim / warmer) under our own registry, derived from the `chainguard-forks/kaniko` upstream.

## Status

- **Status:** active
- **Phase:** Phase 1 — local multi-arch build
- **Owner:** Dennis
- **Upstream:** https://github.com/chainguard-forks/kaniko (Apache-2.0)
- **Plan:** [plans/2026-06-09-build-chainguard-kaniko.md](plans/2026-06-09-build-chainguard-kaniko.md)

## What this project delivers

A reproducible build of four multi-arch kaniko images (linux/amd64, linux/arm64, linux/s390x, linux/ppc64le) using the upstream Dockerfile, plus:

- A single `make images` / `make push` workflow (mirrors upstream)
- A `scripts/build-multiarch.sh` helper that builds a multi-arch manifest list in one pass via `docker buildx`
- A CI workflow (`.github/workflows/images.yaml`) that triggers on `v*` tags and publishes to a registry of our choice
- Optional cosign signing of release tags
- Docs and ADRs capturing the choices

## Layout

```
kaniko-build/
├── README.md                      # this file
├── docs/
│   ├── architecture.md            # how the build + image layout works
│   ├── runbooks/
│   │   └── release.md             # how to cut a release
│   └── references/
│       └── upstream.md            # links + notes on the Chainguard fork
├── plans/
│   ├── 2026-06-09-build-chainguard-kaniko.md   # top-level plan (1 page)
│   └── archive/                   # completed/cancelled plans
├── adrs/
│   ├── README.md                  # chronological index
│   └── 0001-scratch-base-and-multi-arch.md
├── notes/                         # scratch space, meeting notes
├── scripts/
│   └── build-multiarch.sh         # multi-arch buildx helper
├── examples/
│   └── kaniko-build-pod.yaml      # example: kaniko-in-a-pod
└── .github/
    └── workflows/
        └── images.yaml            # CI: build + push on tag
```

## Quick start (local)

```bash
# 1. Login to your registry
docker login ghcr.io -u dverdonschot

# 2. Configure
export REGISTRY=ghcr.io/dverdonschot
export VERSION=v0.1.0-fork1

# 3. Clone upstream once, into a sibling dir
git clone https://github.com/chainguard-forks/kaniko.git ../kaniko-upstream

# 4. Build multi-arch
./scripts/build-multiarch.sh --source ../kaniko-upstream --push
```

For a single-arch smoke test without pushing:

```bash
cd ../kaniko-upstream
REGISTRY=ghcr.io/dverdonschot make images
```

## Pull a pre-built image

This repo's CI publishes multi-arch images to **GHCR** on every `v*` tag. No auth needed — images under `ghcr.io/dverdonschot/kaniko-build` on a public repo are public by default.

The first release is `v0.1.0-fork1`. The image paths are:

```bash
# The default executor (recommended for CI builds in-cluster)
docker pull ghcr.io/dverdonschot/executor:v0.1.0-fork1

# With a busybox shell for debugging
docker pull ghcr.io/dverdonschot/executor:v0.1.0-fork1-debug

# No credential helpers (air-gapped use)
docker pull ghcr.io/dverdonschot/executor:v0.1.0-fork1-slim

# Cache warmer
docker pull ghcr.io/dverdonschot/warmer:v0.1.0-fork1
```

The layout is `ghcr.io/<owner>/<image>:<tag>` where the owner is your GitHub username and the image is either `executor` or `warmer`. Variant is encoded in the tag suffix (`-debug`, `-slim`). For the exact convention see [docs/architecture.md](docs/architecture.md#tagging-convention).

## Verify

```bash
docker pull "${REGISTRY}/executor:${VERSION}"
docker run --rm "${REGISTRY}/executor:${VERSION}" --help
docker pull "${REGISTRY}/warmer:${VERSION}"
docker run --rm "${REGISTRY}/warmer:${VERSION}" --help
```

## Links

- [Plan](plans/2026-06-09-build-chainguard-kaniko.md)
- [Architecture](docs/architecture.md)
- [Release runbook](docs/runbooks/release.md)
- [ADR-0001: scratch base + multi-arch](adrs/0001-scratch-base-and-multi-arch.md)
- [Upstream notes](docs/references/upstream.md)
