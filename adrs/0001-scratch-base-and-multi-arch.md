# 1. Use the `chainguard-forks/kaniko` Dockerfile as-is: `scratch` base, four targets, multi-arch

**Status:** Accepted
**Date:** 2026-06-09
**Deciders:** _(project owner)_

## Context

We need a kaniko image under our control. Two viable paths:

1. **Start from the original Google kaniko Dockerfile.** Multi-stage, `scratch` base, but only amd64/arm64 and Go 1.21.
2. **Use the `chainguard-forks/kaniko` Dockerfile.** Same shape, but Go 1.26, digest-pinned base images, and a four-target multi-arch matrix including s390x and ppc64le.

We also need to decide: do we modify the Dockerfile (e.g. swap to a distroless base for "easier debugging"), or take it as-is?

## Decision

**Use the `chainguard-forks/kaniko` Dockerfile unmodified**, except for one `REGISTRY` line in the Makefile that points builds at our own registry. Build all four named targets (`kaniko-executor`, `kaniko-debug`, `kaniko-slim`, `kaniko-warmer`) for the full multi-arch set: linux/amd64, linux/arm64, linux/s390x, linux/ppc64le.

If we need a shell in production, ship the `kaniko-debug` target. We do **not** maintain a custom base image.

## Consequences

**Easier:**
- Rebasing onto upstream is a clean rebase, not a merge conflict — the Dockerfile is the same.
- Digest-pinned base images make builds reproducible even when `latest` tags move.
- s390x and ppc64le are first-class, no extra work.
- Security review of `deploy/Dockerfile` is a one-time thing; the upstream is already well-audited.

**Harder:**
- No shell in `:latest` / `:slim` — debugging requires the `:debug` target. (Acceptable: that's what `debug` is for.)
- We have to track upstream's Go version cadence. Mitigation: pin by digest and rebase quarterly.
- We can't add custom tooling (e.g. our own credential helper) without forking the Dockerfile. YAGNI for now.

## Alternatives Considered

- **Original `GoogleContainerTools/kaniko`.** Older Go, no s390x/ppc64le. Rejected — we want the broader arch support and the digest-pinning Chainguard added.
- **Distroless base instead of `scratch`.** Adds a shell, libc, ca-certificates Go binary. Useful for ad-hoc debugging, but a worse security baseline. Rejected — `kaniko-debug` covers the debugging case.
- **Build a custom base image.** Total maintenance burden. Rejected — we have no unique requirements the upstream doesn't already cover.
- **Build for amd64 and arm64 only, skip s390x/ppc64le.** Faster CI, but locks us out of IBM Power hosts. Rejected — costs ~5 minutes of extra CI per release.

## References

- Upstream Dockerfile: `deploy/Dockerfile` in https://github.com/chainguard-forks/kaniko
- Upstream workflow: `.github/workflows/images.yaml` in the same repo
- Plan: [plans/2026-06-09-build-chainguard-kaniko.md](../plans/2026-06-09-build-chainguard-kaniko.md)
