# ADR-0002: Running kaniko inside rootless Docker on Fedora Silverblue

**Status:** Proposed
**Date:** 2026-06-12
**Deciders:** _(project owner)_

## Context

We publish a multi-arch kaniko executor image
(`ghcr.io/dverdonschot/executor:<tag>`, see ADR-0001) and want to use it to
build a downstream image on the project owner's Fedora Silverblue
workstation. Silverblue is an immutable, rpm-ostree-based distro, and
the Docker setup on it is necessarily rootless (no privileged
dockerd, by design). Running kaniko inside a rootless dockerd has a
handful of well-known pitfalls that we want to capture up-front so we
don't re-discover them each time.

This ADR covers the rootless-specific decisions only. The choice of
tarball output, the uv-only path, and the PoC scope are all in
[2026-06-12 — Demo Container: Alpine + uv + Python via Kaniko (Rootless)](../plans/2026-06-12-demo-alpine-uv-poc.md)
and its technical refinement.

## Decision

1. **Run the published kaniko executor as a rootless container inside
   rootless Docker, with `--user 0:0`.** The executor's scratch-based
   image is internally unprivileged (ADR-0001) but bind-mounts need to
   write into host-owned directories. Forcing the executor process to
   run as uid 0 inside its own user-namespace avoids the common
   "permission denied on /output" failure mode without changing the
   image.
2. **Bind-mount the build context and output directory from the host,
   both under `$HOME` (or `/tmp`).** Rootless Docker on Linux refuses
   to bind-mount paths the user doesn't own or paths outside its
   configured allow-list. Defaulting to `$HOME` (or `/tmp`, which
   rootless setups typically allow) avoids the most common "no such
   file" error from `docker run -v`.
3. **Write a plain Docker-compatible tarball as the build output, not
   a registry push.** The PoC is local-only; tarballs round-trip
   through `docker load -i` without auth, network, or registry
   dependencies.
4. **Do NOT modify the published kaniko image for rootless.** The
   `--user 0:0` override at the invocation site is enough. The image
   stays as-is, which keeps ADR-0001 and ADR-0002 from conflicting.
5. **Provide a `--no-kaniko` fallback that uses `docker buildx build`
   with `type=tar`.** When rootless-kaniko goes sideways (and it
   will, eventually), the fallback is the fastest way to confirm
   "the Dockerfile itself is fine, this is a kaniko+rootless
   interaction problem" — which is the entire point of this PoC.

## Consequences

- **Easier:** the published image stays single-purpose and unprivileged.
  Rootless-specific logic lives in the calling script, not in the
  image. The same image will keep working in non-rootless CI
  unchanged.
- **Easier:** bind-mounting under `$HOME`/`/tmp` "just works" on the
  common rootless setups (Docker Desktop's rootless mode, plain
  `dockerd-rootless` on Fedora). No `unprivileged-userns` tweaks
  needed for the basic case.
- **Harder:** `--user 0:0` overrides kaniko's own user-namespace
  handling. On systems where rootless Docker is configured to refuse
  the uid-0 mapping (some hardened seccomp profiles do), this will
  fail with a clear `seccomp` or `setrlimit` error. The runbook's
  troubleshooting section covers the next things to try.
- **Harder:** we now have two build paths (kaniko and buildx) to keep
  in sync. The fallback `--no-kaniko` is intentionally minimal: same
  output, same tarball, no registry. If the two ever diverge on the
  resulting image, the script's log makes it obvious which path was
  used.
- **We commit to:** keeping the kaniko image rootless-friendly (no
  setuid binaries, no `chown` of bind-mounted paths from inside the
  executor). This is already true for the scratch-based Chainguard
  fork; we document it here so a future fork doesn't regress.

## Alternatives Considered

- **Use a rootful dockerd for the demo.** Rejected: it would not
  exercise the actual target environment (Silverblue is rootless by
  design), which would defeat the purpose of the PoC.
- **Use `nerdctl` instead of `docker`.** Tempting — `nerdctl` has
  better rootless ergonomics — but it changes the toolchain the
  project owner has on Silverblue. Docker is what's installed; we
  work with what's there.
- **Build with `buildah` instead of kaniko-in-docker.** Rejected for
  this PoC: the goal is to *use* the kaniko image we already publish.
  buildah is the right answer for a different project.
- **Push to a local registry on the box (e.g. `localhost:5000`).**
  Rejected: adds a daemon, adds a port, adds a dependency on
  `skopeo` or `docker push` for the verify step. Tarballs are
  strictly less moving parts for a PoC.

## References

- [ADR-0001 — scratch base + multi-arch](./0001-scratch-base-and-multi-arch.md)
- [Top-level plan: 2026-06-12](../plans/2026-06-12-demo-alpine-uv-poc.md)
- [Technical refinement: 2026-06-12](../plans/2026-06-12-technical-refinement.md)
- [Runbook: demo-build-on-silverblue](../docs/runbooks/demo-build-on-silverblue.md)
- [Docker rootless mode docs](https://docs.docker.com/engine/security/rootless/)
- [kaniko docs: --destination=tar:](https://github.com/GoogleContainerTools/kaniko#--destination)
