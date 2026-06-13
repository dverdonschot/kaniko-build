# Build Chainguard-style Kaniko Images — Plan

**Status:** Approved
**Owner:** _(project owner)_
**Created:** 2026-06-09
**Last updated:** 2026-06-09

## Context

We need a kaniko image that we control end-to-end: a `scratch`-based, multi-arch, signed build, published to our own registry, derived from the well-maintained `chainguard-forks/kaniko` upstream. Reasons:

1. We don't want to depend on Chainguard's release cadence for security fixes.
2. We need a known digest pinned in our cluster manifests, not a moving `:latest`.
3. We want multi-arch (arm64 for the Odroid fleet, s390x/ppc64le for future IBM Power hosts) without maintaining a separate fork.
4. We need cosign signatures on every release.

## Goals

- Build all four upstream targets (executor / debug / slim / warmer) for amd64, arm64, s390x, ppc64le.
- Publish to a registry we own (configurable, default GHCR).
- Reproducible from the upstream Dockerfile, with only `REGISTRY` and a version tag as inputs.
- CI-driven on git tag push; manual `make images` for local smoke tests.
- Optionally signed with cosign.
- Documented runbook for releases and rollbacks.

## Non-Goals

- Modifying kaniko's internals. We take the fork as-is.
- Building for Windows or other non-Linux platforms (kaniko doesn't support them).
- Running our own mirror of upstream; we rebase quarterly.
- Supporting registries without OCI image-manifest support (all major ones do).

## Stakeholders

- **Project owner** — owns the cluster that consumes the images.
- **Future self** — needs the runbook to cut releases without rediscovering the steps.
- **Upstream (`chainguard-forks/kaniko`)** — informs our rebase cadence, not a direct stakeholder.

## High-Level Approach

1. **Track the upstream fork.** Vendor the source into a sibling dir (`../kaniko-upstream`), don't re-host it. Rebase quarterly. The Dockerfile and Makefile are the source of truth.
2. **Single multi-arch build per target.** Use `docker buildx` with QEMU for the non-native architectures. Cache to GHA for fast rebuilds.
3. **CI on tag push.** Tag `vX.Y.Z-forkN` triggers a GitHub Actions workflow that builds and pushes all four multi-arch images, then signs them.
4. **Local escape hatch.** `scripts/build-multiarch.sh` does the same locally for smoke tests.

## Phases

1. **Phase 1: local multi-arch build (this plan).** Get the four images building and pushing from a workstation. ~1 day.
2. **Phase 2: CI on tag push.** `.github/workflows/images.yaml` builds on tag, pushes, signs. ~0.5 day.
3. **Phase 3: production rollout.** Pin a specific digest in our cluster manifests, verify with a real build, document the migration. ~1 day, on-demand.
4. **Phase 4 (cross-cutting):** use the published kaniko image from a
   downstream project to build an actual application image. The
   demo-alpine-uv PoC ([2026-06-12](2026-06-12-demo-alpine-uv-poc.md))
   is the first such consumer and is what proves the kaniko build is
   usable by other projects, not just self-referential.

## Risks

- **QEMU emulation is slow** (~5× slower than native). Mitigation: native builds on arm64/s390x GHA runners (when budget allows); cache aggressively.
- **Upstream Dockerfile drift** (new credential helper, Go bump). Mitigation: quarterly rebase; digest-pinning makes rebases safe.
- **Registry egress costs.** Mitigation: only push on tags, not on every PR. PRs build `linux/amd64` only and discard.
- **Signing key management.** Mitigation: start with keyless cosign (OIDC) for Phase 2; promote to KMS-backed key only if compliance demands it.

## Open Questions

- Which registry do we standardize on for production — GHCR (cheap, no egress fees) or our existing cloud provider's registry (closer to the cluster)?
- Do we need the `debug` image in production, or is it strictly for local troubleshooting?
- Cosign keyless vs KMS-backed — defer until we know our compliance requirements.

## Links

- Architecture: [docs/architecture.md](../docs/architecture.md)
- Release runbook: [docs/runbooks/release.md](../docs/runbooks/release.md)
- ADR-0001: [scratch base + multi-arch](../adrs/0001-scratch-base-and-multi-arch.md)
- Upstream notes: [docs/references/upstream.md](../docs/references/upstream.md)
