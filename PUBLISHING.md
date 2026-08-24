# Publishing the gitguardian kit

This kit is a `kind: mixin`, so it does **not** build a container image - it
layers onto whatever base agent image `--kit` is applied to. "Publishing" here
means pushing the **kit artifact** (the `spec.yaml` plus any `files/`) to an OCI
registry with `sbx kit push`. For a `schemaVersion: "2"` kit this produces a
tar+gzip layer with the spec in the manifest config blob and standard OCI
annotations, so registries and tooling can read kit metadata without pulling
layers.

## Prerequisites

- **A release-channel `sbx` on `PATH` - not a development build.** See
  [Publish from a release build](#publish-from-a-release-build) below; a dev
  build silently produces an artifact that no released `sbx` can resolve.
- `docker login` completed for the target registry - `sbx kit push` uses the
  Docker credential store. For Docker Hub:

  ```console
  docker login -u <dockerhub-id>
  # paste a Docker Hub access token as the password
  ```

## Publish

```console
./scripts/publish.sh                    # docker.io/ajeetraina777/gitguardian-kit:latest
./scripts/publish.sh <namespace>        # docker.io/<namespace>/gitguardian-kit:latest
./scripts/publish.sh <namespace> <tag>
```

or directly:

```console
sbx kit validate ./
sbx kit push ./ docker.io/ajeetraina777/gitguardian-kit:latest
```

The `-kit` suffix in the repo name follows the Docker Sandboxes convention:
`docker.io/<ns>/<kit>-kit` for the artifact, keeping `<kit>-image` free for a
container image (not used by a mixin).

## Pin by digest

`sbx kit push` accepts a `:tag` for convenience, but **consumers must reference
a kit by digest** - the spec's strict-pinning rule rejects OCI tags (including
`:latest`). After pushing, resolve the digest:

```console
docker buildx imagetools inspect docker.io/ajeetraina777/gitguardian-kit:latest | grep -i digest
```

Then consume it:

```console
sbx run claude --kit "oci://docker.io/ajeetraina777/gitguardian-kit@sha256:<digest>" .
```

## Publish from a release build

`sbx kit push` must be run from a **release** build of `sbx`. A development
build writes the kit layer as `application/vnd.oci.empty.v1+json` (a 2-byte
empty descriptor) where a release build writes
`application/vnd.oci.image.layer.v1.tar+gzip`. Released `sbx` clients match on
that media type strictly, so an artifact pushed from a dev build fails to
resolve for every consumer:

```
ERROR: resolve kits: kit "oci://...": no v2 kit layer found in manifest
       (expected media type application/vnd.oci.image.layer.v1.tar+gzip)
```

The push itself reports success, so the breakage only surfaces on the consumer
side. Check before publishing - a `-<n>-g<sha>` suffix means a dev build:

```console
sbx version
# v0.39.0                        <- release, safe to publish
# v0.39.0-rc1-383-g9a702c7a7     <- dev build, do NOT publish
```

`scripts/publish.sh` verifies the layer media type after pushing and fails if
the artifact came out wrong.

## Currently published

- `docker.io/ajeetraina777/gitguardian-kit`
- digest: `sha256:24e7704eee30619a50f6dbfe34ace33772d450c564562283e80ab5b5939b25a0`
  (also tagged `:v039`; pushed from `sbx` v0.39.0 and verified to resolve)

> **Note:** the `:latest` tag currently points at
> `sha256:f37d16488cef8b25aea280fe62e2f360b6c09ac0a83677c0b46b88b567b6acd3`,
> which was pushed from a dev build and **cannot be resolved** by released
> `sbx`. Re-push `:latest` from a release build to fix the tag. Until then,
> ignore `:latest` and pin the digest above.

Re-run the publish step and update this digest whenever `spec.yaml` changes.
Every push rewrites the `org.opencontainers.image.created` annotation, so the
digest changes on each push even when `spec.yaml` is untouched.
