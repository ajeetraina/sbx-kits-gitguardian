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

## One repo, one tag per agent

The kit wires `ggshield` in as a coding agent's **AI hook**, and every agent
uses a different hook file. Rather than a repo per agent, everything lives in a
single repo (`gitguardian-kit`) with **one tag per agent**. Consumers pin by
digest (sbx rejects OCI tags at consume time), so the tag is only a label that
points at the digest to copy.

All the specs are generated from a single template - **edit
`scripts/gen-kits.sh`, not the individual `spec.yaml` files** (they carry a
"generated file" banner):

```console
./scripts/gen-kits.sh          # regenerate spec.yaml + kits/<agent>/spec.yaml
./scripts/gen-kits.sh --check  # fail if any spec is stale (CI/pre-commit gate)
```

| Agent   | Spec source              | Published tag              |
|---------|--------------------------|----------------------------|
| claude  | `spec.yaml` (root)       | `gitguardian-kit:claude` (+ `:latest`) |
| codex   | `kits/codex/spec.yaml`   | `gitguardian-kit:codex`    |
| copilot | `kits/copilot/spec.yaml` | `gitguardian-kit:copilot`  |
| cursor  | `kits/cursor/spec.yaml`  | `gitguardian-kit:cursor`   |

## Publish

```console
./scripts/publish.sh                     # publish ALL agent tags to docker.io/ajeetraina777/gitguardian-kit
./scripts/publish.sh <namespace>         # publish ALL agent tags under <namespace>
./scripts/publish.sh <namespace> <agent> # publish just one tag (claude|codex|copilot|cursor)
```

`publish.sh` runs `gen-kits.sh --check` first (refuses to publish stale specs),
then validates, pushes, and verifies the OCI layer media type for each tag, and
finally publishes claude to `:latest` as the default.

Or push one tag directly:

```console
sbx kit validate ./kits/codex
sbx kit push ./kits/codex docker.io/ajeetraina777/gitguardian-kit:codex
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

Repo `docker.io/ajeetraina777/gitguardian-kit`, one tag per agent. All installed
via `ggshield machine setup --agent <agent> --no-git-hooks --no-honeytokens`,
run as the agent user (uid 1000; no git hooks):

| Tag        | Agent   | Digest to pin |
|------------|---------|---------------|
| `:claude`  | claude  | `sha256:8a3ad30666e6e651e4fff3c56a16e715bff4ac5356512c7dcbaa47f97988e8c4` |
| `:codex`   | codex   | `sha256:532a1a328fbc01a996e2e17f8053f297fd72a11026276f6e4021cc33a7ea0782` |
| `:copilot` | copilot | `sha256:cd38bfb3c9affd4d723fe4d97c0a6e08b427645a17efcc3c43dbb59ca21d3e02` |
| `:cursor`  | cursor  | `sha256:f92a932951174cbc1378a22fa56d0b779fc6e136eff8f42fc6c094fc83cd7cbd` |
| `:latest`  | claude  | `sha256:5b01ab79c69988ae87ecfccfc108f25193a6c14385122b8e6db4bc0005f7dfed` (same spec as `:claude`, distinct digest) |

Superseded (do not use): the short-lived per-agent repos
`gitguardian-kit-codex` / `-copilot` / `-cursor`, and older `gitguardian-kit`
digests `sha256:1c87b514…` (single-agent AI-hook build), `sha256:e276e93d…`
(now-reverted git hooks), `sha256:24e7704e…` (pre-enforcement).

Pushed from `sbx` v0.39.0 (release build) and verified to carry a
`application/vnd.oci.image.layer.v1.tar+gzip` kit layer.

Re-run `./scripts/publish.sh` and update these digests whenever a spec changes.
Every push rewrites the `org.opencontainers.image.created` annotation, so the
digest changes on each push even when the spec is untouched.

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
