# Upstream: chainguard-forks/kaniko

## Source

- **Repo:** https://github.com/chainguard-forks/kaniko
- **License:** Apache-2.0
- **Branch:** `main`
- **Original:** https://github.com/GoogleContainerTools/kaniko (the Chainguard fork carries hardening + a Go update + multi-arch matrix)

## Why the fork, not the original

The Chainguard fork:

1. Bumps Go to 1.26 (vs. older in upstream Google org).
2. Pins base images by digest in the Dockerfile (`golang:1.26@sha256:...`, `debian:bookworm-slim@sha256:...`, `busybox:musl@sha256:...`) — supply-chain hardening.
3. Ships a multi-arch matrix including s390x and ppc64le (the original only built amd64/arm64).
4. Uses a single multi-stage `deploy/Dockerfile` with four named targets — simpler than the original's split files.

That's exactly what we want: deterministic, multi-arch, minimal.

## How we track it

Strategy: **vendor + pin by digest**, rebase quarterly.

- The Dockerfile already pins base images by SHA256 — we don't need to track those manually.
- We DO need to rebase our fork onto `chainguard-forks/kaniko:main` periodically to pick up Go updates, new credential helpers, and any security fixes.
- Concretely:
  ```bash
  git fetch upstream
  git rebase upstream/main
  # resolve any conflicts (typically the Makefile REGISTRY line we customized)
  ```

## Things we deliberately do NOT carry forward

- We don't adopt their `cosign.pub` key — we use our own (see [ADR-0001](../adrs/0001-scratch-base-and-multi-arch.md) for the why).
- We don't push to `cgr.dev/chainguard/*` — only to our own `REGISTRY`.
- We don't run the upstream release script (`hack/release.sh`); we use GitHub tag-driven CI instead.

## Useful upstream files

- `deploy/Dockerfile` — the build, single source of truth.
- `Makefile` — `make images` / `make push` targets (we copy the relevant parts into our `scripts/build-multiarch.sh`).
- `.github/workflows/images.yaml` — the matrix definition (we adapt it for our registry + signing).
- `integration/` — gold-standard integration tests. Run them against our built images before each release.
