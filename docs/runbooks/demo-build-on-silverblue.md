# Runbook: Building the demo-alpine-uv container on Fedora Silverblue

This runbook walks through the end-to-end proof of concept: use the
published kaniko executor (built in the sibling plan) to build a small
demo container on a Fedora Silverblue box running rootless Docker.

## Prerequisites

- Fedora Silverblue (or another rpm-ostree-based Fedora) with
  **rootless Docker**. Verify with:
  ```bash
  docker info | grep -i rootless
  # expect:  Server: ... <something>
  # then:    Security Options: ... rootless
  # or check: docker context inspect | grep Endpoint
  ```
- A user account that owns `$HOME` and can run `docker` without
  `sudo` (i.e. you're in the `docker` group, or the rootless setup
  tool has wired up the user namespace for you).
- Network access to `ghcr.io` (for the initial pull of the kaniko
  executor) and to `astral.sh` + `python.org` (for the uv installer
  and Python download at build time inside the demo Dockerfile).
- This repo cloned somewhere under `$HOME` (rootless Docker can be
  picky about bind-mount sources outside the user's home).

## Decide which rootless mode you're on

There are two common ways Docker ends up "rootless" on Silverblue.
They expose the same `docker` CLI but the underlying mechanics differ
in ways that matter for kaniko:

1. **Docker Desktop's "Use rootless mode"** — user-namespaces managed
   by the desktop VM. The default `--user 0:0` in `build-demo.sh`
   works.
2. **`dockerd-rootless-setuptool.sh` on a stock `docker-ce` install** —
   user-namespaces managed by `slirp4netns` (or `rootlesskit`). The
   default also works, but bind-mounts from `/tmp` are usually fine
   too.

If unsure, run `docker info` and look for `Rootless: true` near the
top. Both are supported by the script; this runbook is valid for
both.

## The run, step by step

```bash
# 1. Move to the repo on the Silverblue box
cd ~/projects/kaniko-build    # or wherever you cloned it

# 2. (First run only) pull the kaniko executor
docker pull ghcr.io/dverdonschot/executor:v0.1.0-fork1

# 3. Build the demo
./scripts/build-demo.sh
# defaults:
#   context       = examples/demo-alpine-uv
#   dockerfile    = Dockerfile.demo
#   kaniko-image  = ghcr.io/dverdonschot/executor:v0.1.0-fork1
#   output        = /tmp/demo-oci/demo-alpine-uv-dev.tar
#   tag           = dev
#
# Output ends up in /tmp/demo-oci/.

# 4. Verify
./scripts/verify-demo.sh
# Loads the tarball, runs the container three times:
#   uv --version
#   python --version
#   uv run python -c 'print(1+1)'   (must print 2)
```

A successful run prints, at the end:

```
[verify-demo] check 1/3: uv --version
  uv 0.x.y
[verify-demo] check 2/3: python --version
  Python 3.x.y
[verify-demo] check 3/3: uv run python -c "print(1+1)"
  2
[verify-demo] all checks passed
```

## Common flags

```bash
# Custom output dir under $HOME (recommended over /tmp on Silverblue if
# /tmp is tmpfs and the image is large):
./scripts/build-demo.sh --output $HOME/demo-oci

# Different tag for the produced image:
./scripts/build-demo.sh --tag test1

# Use a different published kaniko image:
./scripts/build-demo.sh --kaniko-image ghcr.io/dverdonschot/executor:other-tag

# Fall back to docker buildx (no kaniko), to confirm the Dockerfile is
# OK in isolation:
./scripts/build-demo.sh --no-kaniko
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `docker load` fails: `failed to register layer ... permission denied` | `/tmp` is `tmpfs` and the tarball is bigger than available RAM | Use `--output $HOME/demo-oci` and re-run |
| kaniko errors with `error mounting ... /output: permission denied` | bind-mount of `/tmp` or other path refused by rootless dockerd | Move `--output` under `$HOME` |
| kaniko errors with `seccomp` or `setrlimit` related messages | rootless kernel config or seccomp profile blocks `--user 0:0` | Edit `build-demo.sh` to drop the `--user 0:0` line and re-run; if that fixes it, document the kernel config in this runbook |
| `uv-install.sh` download fails inside the build | No network access from inside the build context | The kaniko executor pulls base images; if the host has a proxy, pass `--build-arg HTTP_PROXY=...` to kaniko via a future `--build-arg` flag in the script |
| `uv python install` fails with checksum error | Transient `python.org` issue, or proxy mangles the download | Re-run the script; if it persists, add `--no-cache` to the `uv python install` line in the Dockerfile |
| `verify-demo.sh` reports `uv: not found` even though the tarball loaded | The Dockerfile's `UV_INSTALL_DIR` env didn't take effect (typo, wrong shell quoting) | Re-check `examples/demo-alpine-uv/Dockerfile.demo`'s `ENV UV_INSTALL_DIR=/usr/local/bin` line; rebuild |
| Everything works locally but CI uses different kaniko image | `--kaniko-image` not pinned | Use `--kaniko-image` explicitly; consider adding it to a `Makefile` or env-var default |

## Recording the run

The whole point of the PoC is to capture the actual output of a real
run for the ADR and for future reference. After a successful run:

```bash
# Save the verify output for the notes/ folder
./scripts/verify-demo.sh 2>&1 | tee notes/2026-06-12-silverblue-run.md

# Or, after the fact, hand-capture the relevant lines into
# notes/2026-06-12-silverblue-run.md with a short narrative
# (host kernel version, rootless mode, total elapsed time, anything
# from the Troubleshooting table that actually happened).
```

## What "done" looks like

The PoC is done when all three of these are true:

1. `./scripts/build-demo.sh` exits 0 on Silverblue.
2. `./scripts/verify-demo.sh` prints "all checks passed".
3. The notes file `notes/2026-06-12-silverblue-run.md` exists with the
   real captured output and any ADR-0002 updates that turned out to be
   needed.

If the kaniko-in-rootless path turns out to be impractical, the
fallback is: declare the PoC done with the `--no-kaniko` path, and
note in `notes/` that the next iteration of the published kaniko
image needs rootless-specific tweaks (which would feed into
ADR-0002's "Consequences" section as a revision).
