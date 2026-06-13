# demo-alpine-uv

A deliberately small example that uses the published kaniko image
(from the sibling plan) to build a container from scratch:

- Base: `alpine:3.20`
- Installed by hand: `curl`, `ca-certificates`, `bash` via `apk`
- Installed by hand: `uv` via the official Astral installer
- Provisioned by hand: Python via `uv python install`
- Entrypoint: `uv` (so `docker run demo-alpine-uv:dev --version` works)

This is a **proof of concept**, not a reusable pipeline. The goal is to
prove the full chain works on the project owner's Fedora Silverblue box
with rootless Docker:

```
Dockerfile.demo  →  kaniko executor (our published image)  →  tarball
                                                                  │
                                                                  ▼
                                                  docker load + docker run
                                                  (assert uv + python work)
```

## Quick start

```bash
# From the repo root, with the project owner's Fedora Silverblue box
# running rootless Docker:
./scripts/build-demo.sh
./scripts/verify-demo.sh
```

The default `kaniko-image` is the tag published by the sibling plan
(`v0.1.0-fork1` at the time of writing). Override with `--kaniko-image`
if a newer fork has shipped.

## Why a tarball, not a registry push

The PoC is local-only — no `--push`. The script writes a plain
Docker-compatible tarball to the host (default `/tmp/demo-oci/`,
filename `demo-alpine-uv-<tag>.tar`) which `docker load -i` accepts
directly. See
[plans/2026-06-12-technical-refinement.md](../../plans/2026-06-12-technical-refinement.md)
for the full reasoning.

## Files

- `Dockerfile.demo` — the build context
- `../../scripts/build-demo.sh` — runs kaniko, produces the tarball
- `../../scripts/verify-demo.sh` — loads the tarball, runs the
  container, asserts `uv --version`, `python --version`, and a
  `uv run python -c '...'` smoke test all succeed
- `../../docs/runbooks/demo-build-on-silverblue.md` — step-by-step
  runbook for the Silverblue run
- `../../adrs/0002-rootless-kaniko-on-silverblue.md` — rootless-specific
  decisions and pitfalls
