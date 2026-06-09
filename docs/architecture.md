# Architecture

## What we're building

Four container images, all derived from the same Go source in the `chainguard-forks/kaniko` repo, all based on `scratch`, all multi-arch (linux/amd64, linux/arm64, linux/s390x, linux/ppc64le):

| Target            | Image tag suffix | Base        | Purpose                                      | Platforms                              |
|-------------------|------------------|-------------|----------------------------------------------|----------------------------------------|
| `kaniko-executor` | `latest`         | scratch     | The default executor (build OCI images in-cluster) | amd64, arm64, s390x, ppc64le           |
| `kaniko-debug`    | `debug`          | scratch + busybox | Same executor with busybox shell on PATH for debugging | amd64, arm64, s390x |
| `kaniko-slim`     | `slim`           | scratch     | Executor without the cloud-credential helpers (for air-gapped use) | amd64, arm64, s390x, ppc64le           |
| `kaniko-warmer`   | `warmer`         | scratch     | Pre-warms the layer cache for a remote registry | amd64, arm64, s390x, ppc64le           |

## Build pipeline

```
   ┌────────────────────────────┐
   │  chainguard-forks/kaniko  │  (Go source + deploy/Dockerfile)
   │  vendored deps, Go 1.26   │
   └────────────┬───────────────┘
                │  docker buildx build
                │  (4 targets, multi-arch)
                ▼
   ┌────────────────────────────┐
   │  GHA cache (mode=max)     │  (for fast rebuilds)
   └────────────┬───────────────┘
                │
                ▼
   ┌────────────────────────────┐
   │  Registry (GHCR / GCR /   │
   │  ECR / Docker Hub)         │
   │  cgr.dev/ORG/kaniko:*     │
   └────────────────────────────┘
```

Stages inside the Dockerfile (from `deploy/Dockerfile` in the upstream repo):

1. `builder` — `golang:1.26` image, compiles `executor` and `warmer` statically (`CGO_ENABLED=0`), and `go install`s three cloud-credential helpers (GCR, ECR, ACR).
2. `certs` — `debian:bookworm-slim`, produces a fresh `/etc/ssl/certs/ca-certificates.crt` bundle.
3. `busybox` — `busybox:musl`, a static busybox used only by the `debug` target.
4. `kaniko-base-slim` — `scratch` + certs + nsswitch + the writable `/kaniko` dir.
5. `kaniko-base` — `kaniko-base-slim` + the three credential helpers + `/kaniko/.docker/`.
6. `kaniko-executor` / `kaniko-warmer` / `kaniko-debug` / `kaniko-slim` — the final four targets, each picking what it needs from earlier stages.

## Build matrix (from `.github/workflows/images.yaml`)

The upstream workflow builds on every PR for `linux/amd64` only, and on every tag push for the full multi-arch set. We mirror that in `.github/workflows/images.yaml` in this project.

## What's intentionally NOT included

- No shell in the production images — `scratch` is the base. The `debug` target is the only escape hatch.
- No package manager, no libc, no `ca-certificates` Go binary — only the cert bundle as a file.
- No customer/vendor brand names anywhere. The `REGISTRY` is configurable; we don't hardcode any provider.

## Tagging convention

```
<REGISTRY>/executor:<version>          # latest default
<REGISTRY>/executor:<version>-debug
<REGISTRY>/executor:<version>-slim
<REGISTRY>/warmer:<version>
```

Where `<version>` is the git tag we push (e.g. `v1.25.0-fork1`). We do not publish `:latest` from CI — only versioned tags — to make rollbacks deterministic.
