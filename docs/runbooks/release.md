# Release runbook

How to cut a new release of our kaniko images.

## Prerequisites

- Write access to this repo
- `docker buildx` configured locally (or rely on CI)
- Registry credentials: `docker login <REGISTRY>`
- cosign installed (for signing)

## 1. Decide the version

Bump rules:

- **Patch** (`v0.1.0-fork1` → `v0.1.0-fork2`): security fix, credential-helper update, Go patch.
- **Minor** (`v0.1.0-fork1` → `v0.2.0-fork1`): rebase onto newer upstream, Go minor bump.
- **Major**: don't. We track the upstream major.

## 2. Rebase onto upstream (if needed)

```bash
git remote add upstream https://github.com/chainguard-forks/kaniko.git
git fetch upstream
git rebase upstream/main
# resolve conflicts — typically just the Makefile REGISTRY line
git push --force-with-lease
```

## 3. Tag and push

```bash
VERSION=v0.1.0-fork1   # or whatever the next version is
git tag -s "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"
```

The tag push triggers `.github/workflows/images.yaml`, which builds all four targets for the full multi-arch set and pushes them to `ghcr.io/dverdonschot/{executor,warmer}:<version>[-<variant>]`.

If the workflow fails on action-resolution time (e.g. a SHA we pinned doesn't exist on the GHA index), fix the SHA, delete and re-push the tag:

```bash
git tag -d "$VERSION"
git push origin :refs/tags/"$VERSION"
# fix the workflow
git push origin main
git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"
```

## 4. Watch CI

- Open the Actions tab on the tag push.
- The job takes 20–30 minutes (per upstream's own estimate).
- If anything fails, delete the tag, fix, re-tag. **Do not** force-push tags.

## 5. Verify

```bash
docker pull "${REGISTRY}/executor:${VERSION}"
docker pull "${REGISTRY}/executor:${VERSION}-debug"
docker pull "${REGISTRY}/executor:${VERSION}-slim"
docker pull "${REGISTRY}/warmer:${VERSION}"

docker run --rm "${REGISTRY}/executor:${VERSION}" --help
docker run --rm "${REGISTRY}/warmer:${VERSION}" --help

# (Optional) Run the upstream integration test suite against our build
cd ../kaniko-upstream && REGISTRY=... VERSION=... ./scripts/integration-test.sh
```

## 6. Sign (optional, recommended)

```bash
cosign sign --yes "${REGISTRY}/executor@$(crane digest "${REGISTRY}/executor:${VERSION}")"
cosign sign --yes "${REGISTRY}/warmer@$(crane digest "${REGISTRY}/warmer:${VERSION}")"
```

## 7. Announce

- Update the `Last reviewed` date in `~/projects/INDEX.md` for this project.
- Drop a one-line note in `notes/` with the release date and version.

## Rollback

Tags are immutable. To roll back, point consumers at the previous tag. There's nothing to "undo" on the registry side unless the images were never used.

## When things go wrong

| Symptom                              | Cause                          | Fix                                                                 |
|--------------------------------------|--------------------------------|---------------------------------------------------------------------|
| CI fails on `docker/build-push-action` | Registry creds expired       | Rotate the `REGISTRY_TOKEN` secret, re-run the workflow             |
| One platform fails to build           | QEMU/binfmt issue on runner    | Pin QEMU to a known good version in the workflow                    |
| Image runs but `docker push` inside kaniko fails | Missing cred helper in slim target | Use the `executor` tag, not `executor-slim`, for cloud registries |
| Cert errors                          | Upstream `debian:bookworm-slim` digest rotated | Re-pin the digest in the Dockerfile, re-tag, push                |
