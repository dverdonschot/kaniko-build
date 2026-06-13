# Technical Refinement: Demo Container (alpine + uv + Python) via Rootless Kaniko

**Status:** Draft
**Parent plan:** [2026-06-12 — Demo Container: Alpine + uv + Python via Kaniko (Rootless)](2026-06-12-demo-alpine-uv-poc.md)
**Owner:** _(project owner)_
**Created:** 2026-06-12
**Last updated:** 2026-06-12

## Overview

This refinement specifies exactly how `scripts/build-demo.sh` will run kaniko
inside rootless Docker to produce a local image tarball, and how
`scripts/verify-demo.sh` will prove the resulting image works. The
deliverable is a runnable pair of scripts plus a working `Dockerfile.demo`,
not a reusable framework.

## Current State

We have:

- A published multi-arch kaniko executor at
  `ghcr.io/dverdonschot/executor:<tag>` (from the sibling plan, default
  `v0.1.0-fork1`).
- A `scripts/build-multiarch.sh` that builds the *kaniko* images via buildx
  (this is the tool-builder, not a tool-user).
- No example yet of a downstream project actually *using* the published
  kaniko image to build something else.

## Proposed Approach

### Components

- **Name:** `examples/demo-alpine-uv/Dockerfile.demo`
- **Purpose:** Build context consumed by kaniko. Produces an `alpine:3.20`
  base with `uv` installed via the official installer and a Python
  interpreter provisioned via `uv python install`. Named `Dockerfile.demo`
  (not `Dockerfile`) so it's obvious this isn't the main artifact of the
  repo.
- **Interface:** A standard Dockerfile.
- **Dependencies:** Network access during build (for the uv installer and
  the Python download), an `alpine:3.20` base, `curl`, `ca-certificates`.

- **Name:** `scripts/build-demo.sh`
- **Purpose:** Runs the published kaniko executor in a container, with the
  build context and output directory bind-mounted from the host. Writes a
  plain Docker-compatible tarball to the host (no registry push). Includes
  a `--no-kaniko` fallback that uses `docker buildx build` instead, so we
  can diff the two outputs during the proof.
- **Interface:** CLI flags `--context`, `--dockerfile`, `--kaniko-image`,
  `--no-kaniko`, `--output`, `--tag`. Help and error paths return
  non-zero with a clear message.
- **Dependencies:** Docker CLI with buildx, the published kaniko image
  (or buildx for the fallback), a writable output directory on the host.

- **Name:** `scripts/verify-demo.sh`
- **Purpose:** Loads the produced tarball into the local Docker daemon as
  `demo-alpine-uv:<tag>`, runs the container, and asserts that
  `uv --version`, `python --version`, and a `uv run python -c '...'` smoke
  test all succeed.
- **Interface:** CLI flag `--image <path>` defaulting to the tarball
  produced by `build-demo.sh`. Help and error paths return non-zero with
  a clear message.
- **Dependencies:** Docker CLI.

### Data Flow

```
+-----------------+         +----------------------+         +------------------+
| examples/       |  bind   |  kaniko executor     |  writes | /output/         |
| demo-alpine-uv/ | ──────► |  (our published img) | ──────► | demo-alpine-uv-  |
+-----------------+         +----------------------+         | dev.tar          |
                                                                 │
                                                                 │ docker load -i
                                                                 ▼
                                                        +------------------+
                                                        | demo-alpine-uv:  |
                                                        |   dev (in        |
                                                        | dockerd)         |
                                                        +------------------+
                                                                 │
                                                                 │ docker run
                                                                 ▼
                                                        uv --version
                                                        python --version
                                                        uv run python -c '...'
```

### Configuration

| Knob              | Default                                       | Override         | Notes                                              |
|-------------------|-----------------------------------------------|------------------|----------------------------------------------------|
| `--context`       | `examples/demo-alpine-uv`                     | path             | Build context, bind-mounted to `/workspace` in kaniko |
| `--dockerfile`    | `Dockerfile.demo`                             | path             | Relative to `--context`                            |
| `--kaniko-image`  | `ghcr.io/dverdonschot/executor:v0.1.0-fork1`   | image ref        | Override the pinned tag when needed                |
| `--output`        | `/tmp/demo-oci` (note: actually a tarball; named after the OCI-layout path it was designed around; see "Refinement vs plan" delta below) | dir              | Tarball goes at `<output>/demo-alpine-uv-<tag>.tar` |
| `--tag`           | `dev`                                         | string           | Image tag inside the produced tarball              |
| `--no-kaniko`     | off                                           | flag             | Fall back to `docker buildx build` for comparison   |

The defaults assume the published kaniko image is reachable from the host
(public GHCR image, no auth). On Silverblue the first run will pull it.

### Why tarball, not registry or OCI layout

Kaniko supports `--destination=tar:/output/demo-image.tar` to write a plain
Docker-compatible tarball in one step. We prefer this over:

- `--push` to a registry: the PoC is local-only (per the plan's "Where
  published" decision), and a registry introduces auth and network
  dependencies that aren't needed.
- `--destination=oci:/output`: produces an OCI image layout, which then
  needs `skopeo` or `docker buildx imagetools` to convert. The tarball
  path is `docker load -i` and done, which is the lowest-friction local
  verification.

### Why bind-mount `/output` and not a named volume

A named volume would work too, but bind-mounts are easier to inspect from
the host (`ls -lh /tmp/demo-oci/`) and easier to clean up (`rm -rf`). On
rootless Docker the bind mount must be inside the user's home directory
or a path the rootless dockerd is configured to allow. The script will
warn if the chosen `--output` is outside `$HOME`.

### Refinement vs plan delta: tarball, not OCI tarball

The top-level plan text says "output a plain OCI tarball." This refinement
specifies a plain **Docker-compatible** tarball (the kind `docker load`
consumes) rather than an OCI image-layout tarball. The two are different
formats. Docker tarballs are the right choice for a PoC because `docker
load` accepts them directly. The plan will be patched to say "plain
Docker-compatible tarball" in a follow-up — keeping this delta visible
here for the next reader.

### Testing Strategy

- **Static (in CI / pre-push):** `bash -n scripts/build-demo.sh`,
  `bash -n scripts/verify-demo.sh`, both scripts' `--help` runs cleanly,
  both error paths run cleanly (e.g. build-demo.sh with no args,
  build-demo.sh with a non-existent context).
- **Smoke (Phase 2, this dev box, rootful dockerd):** End-to-end run
  produces a tarball, `docker load` succeeds, `python --version` works
  inside the container.
- **Real (Phase 3, Silverblue, rootless):** Same as smoke but on the
  actual target. Records actual output to
  `notes/2026-06-12-silverblue-run.md`. Captures the kaniko container
  logs to that file in case ADR-0002 needs an update.

### Rollout Plan

There is no rollout — this is a local exercise. The "rollback" if it
doesn't work is to delete `examples/demo-alpine-uv/`,
`scripts/build-demo.sh`, `scripts/verify-demo.sh`, the runbook, and
ADR-0002. The plan and this refinement can stay as a record of what
was tried.

## Tasks

- [x] Top-level plan drafted
- [ ] Dockerfile.demo written and syntax-checked
- [ ] `scripts/build-demo.sh` written, `bash -n` passes, `--help` works,
      error paths return non-zero with a clear message
- [ ] `scripts/verify-demo.sh` written, `bash -n` passes, `--help` works
- [ ] ADR-0002 drafted
- [ ] Runbook drafted
- [ ] Update plan text: "OCI tarball" → "Docker-compatible tarball"
- [ ] Update README, plans/README.md, adrs/README.md, INDEX.md
- [ ] Smoke test on this dev box (Phase 2)
- [ ] Real test on Silverblue (Phase 3)
