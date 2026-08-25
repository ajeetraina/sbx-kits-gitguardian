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
- digest: `sha256:e276e93df0c80555ab83b90ce1e93c0b4d4ce78e12b34572de393fd9b9fd20bd`
- tags: `:latest` points at the digest above (adds the global ggshield
  pre-commit + pre-push git hooks). `:v039` still points at the previous,
  pre-hooks digest `sha256:24e7704eee30619a50f6dbfe34ace33772d450c564562283e80ab5b5939b25a0`
  - retag it (see below) if you want `:v039` to include hook enforcement.

Pushed from `sbx` v0.39.0 (release build) and verified to carry a
`application/vnd.oci.image.layer.v1.tar+gzip` kit layer.

Re-run the publish step and update this digest whenever `spec.yaml` changes.
Every push rewrites the `org.opencontainers.image.created` annotation, so the
digest changes on each push even when `spec.yaml` is untouched.

## Retag without re-publishing

Because each push mints a new digest, moving a tag onto an *existing*, already
verified artifact is safer than re-pushing: PUT the same manifest bytes under
the new tag. The digest is unchanged, so nothing pinned in the docs has to move
and no blob upload is needed (the config and layer are already in the repo).

```console
REPO=ajeetraina777/gitguardian-kit
DIG=sha256:e276e93df0c80555ab83b90ce1e93c0b4d4ce78e12b34572de393fd9b9fd20bd
TOK=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${REPO}:pull,push" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

curl -sf -H "Authorization: Bearer $TOK" \
  -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "https://registry-1.docker.io/v2/${REPO}/manifests/${DIG}" -o manifest.json

# confirm the bytes hash to the digest you expect before pushing the tag
sha256sum manifest.json

curl -s -X PUT -H "Authorization: Bearer $TOK" \
  -H "Content-Type: application/vnd.oci.image.manifest.v1+json" \
  --data-binary @manifest.json \
  "https://registry-1.docker.io/v2/${REPO}/manifests/latest"
```
