# Demo Container: Alpine + uv + Python via Kaniko (Rootless)

**Status:** Draft
**Owner:** _(project owner)_
**Created:** 2026-06-12
**Last updated:** 2026-06-12

## Context

We already publish a self-hosted kaniko image (see
[2026-06-09 — Build Chainguard-style Kaniko images](2026-06-09-build-chainguard-kaniko.md)).
That gets us the *tool*; we don't yet have any project *using* it.

This plan closes that loop with a deliberately small, throwaway demo: build an
`alpine` container that installs `uv` and provisions a Python interpreter
entirely by hand (no `python:` base image, no `pip install uv`). The goal is
not the resulting image — it's to prove the full chain works on a real
workstation:

```
  Dockerfile  ──►  kaniko executor (our published image)  ──►  tarball
                                                                       │
                                                                       ▼
                                              docker load  ◄──  /tmp/demo-image.tar
                                                       │
                                                       ▼
                                        docker run (verify python + uv)
```

Target host for the proof: **the project owner's Fedora Silverblue PC, with
rootless Docker**
Docker** (Docker Desktop's rootless mode, or `dockerd-rootless-setuptool.sh`
on a Podman box — we don't assume which yet, the runbook covers both).

## Goals

- Demonstrate that the published kaniko image runs unchanged inside rootless
  Docker on Fedora Silverblue.
- Produce a working `demo-alpine-uv` image (alpine base, `uv` installed via the
  official installer, `python` provisioned via `uv python install`).
- Output a plain Docker-compatible tarball — **no registry push** — so
  the proof is fully self-contained and reproducible offline after the
  initial kaniko image pull.
- Verification: `docker load` + `docker run` and assert that
  `python --version` and `uv --version` both succeed.
- Document the rootless quirks we hit (in an ADR + runbook) so the next
  person running this doesn't re-discover them.
  doesn't re-discover them.

## Non-Goals

- A reusable pipeline template (this is a PoC, not a framework).
- CI integration in this repo (the kaniko image already has its own CI; this
  is a manual local exercise).
- Pushing the demo image to GHCR or any registry.
- Multi-arch builds (single-arch `linux/amd64` is enough for the proof).
- Pinning Python or `uv` to a specific version. We install whatever the
  official installer serves at run time.
- Modifying the published kaniko image.

## Stakeholders

- **Project owner** — runs the build on Silverblue, decides if the chain is
  "good enough" to call this PoC done.
- **Future self** — reads the runbook and the ADR when redoing this on a new
  machine.

## High-Level Approach

1. **New folder `examples/demo-alpine-uv/`.** A `Dockerfile.demo` that starts
   from `alpine:3.20`, runs `apk add curl ca-certificates`, then downloads
   `https://astral.sh/uv/install.sh` to `/uv-install.sh`, runs it, and finally
   runs `uv python install` so the image ships a real interpreter. `ENTRYPOINT
   ["uv"]`. We use `Dockerfile.demo` (not `Dockerfile`) to make it obvious
   this isn't the main artifact of the repo.
2. **New script `scripts/build-demo.sh`.** A thin wrapper that:
   - Asserts the host is actually running rootless Docker (`docker info |
     grep -i rootless`).
   - Runs the published kaniko image in a container, with `/workspace` and
     `/output` bind-mounted from the host, `--context=/workspace`, and
     `--destination=oci:/output/demo-image:dev` so the result is a plain OCI
     layout directory (not a registry push).
   - Falls back to building with buildx natively if `--no-kaniko` is passed
     (so we can diff the two outputs during the proof).
3. **New `scripts/verify-demo.sh`.** Runs `docker load` on the produced
   tarball, then `docker run --rm demo-alpine-uv:dev python --version` and
   `... uv --version`. Exits non-zero if either fails.
4. **New ADR-0002** capturing the rootless-kaniko-on-Silverblue specifics:
   user-namespace handling, why we use the OCI layout destination, why we
   avoid `--push`, what we did NOT have to change in our published kaniko
   image.
5. **New runbook `docs/runbooks/demo-build-on-silverblue.md`** with the exact
   commands, in order, plus the "if X goes wrong, check Y" decision tree.

## Phases

1. **Phase 1: write the artifacts (this plan).** All files added to the repo,
   not yet executed. ~1 hour.
2. **Phase 2: smoke test on this dev box** (Ubuntu, rootful dockerd — good
   enough to catch script bugs and Dockerfile syntax errors). ~30 min.
3. **Phase 3: real run on Silverblue.** The project owner runs
   `scripts/build-demo.sh` on
   the Fedora box, we record the actual output in `notes/`. Time-on-machine,
   any failures, any ADR updates needed. ~1 hour including troubleshooting.

## Risks

- **uv installer network call inside the build.** Mitigated by the kaniko
  image already being scratch-based with no network restrictions we know of;
  if it fails we'll add `--build-arg HTTP_PROXY=...` later. Not worth solving
  pre-emptively for a PoC.
- **alpine 3.20 base may be EOL by the time we re-run this.** Mitigation:
  bump the tag in the Dockerfile when we hit it; the script doesn't pin it
  in any meaningful way.
- **Rootless Docker on Silverblue may not allow the kaniko executor's
  user-namespace dance.** This is the most likely real failure mode.
  Mitigation: the runbook's troubleshooting section pre-empts the common
  symptoms (permission denied on `/output`, `setrlimit` errors, etc.).
- **The published kaniko image is large** (~hundreds of MB). The first pull
  on Silverblue will take a while. Not a code risk, just a UX note in the
  runbook.

## Open Questions

- Are we running Docker Desktop's "rootless" setting on Silverblue, or
  Podman's `docker` compatibility mode? Both expose the same `docker` CLI but
  have different rootless mechanics. (Runbook will need a "which one are
  you on" branch.)
- Should the runbook recommend a specific `kaniko-image` tag, or always pull
  `:latest-fork1`? Tag-pinning is safer; we'll pin to the version that was
  current when this plan was written, with a one-liner in the runbook on how
  to bump it.
- Do we want a `make demo` target as a shortcut, or is `scripts/build-demo.sh`
  enough for a PoC? Leaning "no Makefile, keep it a script" — fewer moving
  parts.

## Links

- Parent project: [README.md](../README.md)
- Sibling plan: [2026-06-09 — Build Chainguard-style Kaniko images](2026-06-09-build-chainguard-kaniko.md)
- Technical refinement: [2026-06-12 — Technical refinement](2026-06-12-technical-refinement.md)
- ADR-0002: [Rootless kaniko on Fedora Silverblue](../adrs/0002-rootless-kaniko-on-silverblue.md)
- Runbook: [docs/runbooks/demo-build-on-silverblue.md](../docs/runbooks/demo-build-on-silverblue.md)
- Artifact: [examples/demo-alpine-uv/](../examples/demo-alpine-uv/)
- Build script: [scripts/build-demo.sh](../scripts/build-demo.sh)
- Verify script: [scripts/verify-demo.sh](../scripts/verify-demo.sh)
