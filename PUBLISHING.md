# Publishing the gitguardian kit

This kit is a `kind: mixin`, so it does **not** build a container image — it
layers onto whatever base agent image `--kit` is applied to. "Publishing" here
means pushing the **kit artifact** (the `spec.yaml` plus any `files/`) to an OCI
registry with `sbx kit push`. For a `schemaVersion: "2"` kit this produces a
tar+gzip layer with the spec in the manifest config blob and standard OCI
annotations, so registries and tooling can read kit metadata without pulling
layers.

## Prerequisites

- `sbx` on `PATH`.
- `docker login` completed for the target registry — `sbx kit push` uses the
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
a kit by digest** — the spec's strict-pinning rule rejects OCI tags (including
`:latest`). After pushing, resolve the digest:

```console
docker buildx imagetools inspect docker.io/ajeetraina777/gitguardian-kit:latest | grep -i digest
```

Then consume it:

```console
sbx run claude --kit "oci://docker.io/ajeetraina777/gitguardian-kit@sha256:<digest>" .
```

## Currently published

- `docker.io/ajeetraina777/gitguardian-kit:latest`
- digest: `sha256:ee59d27a3d985f1aae33c714db99b434f20fca52f7e70bf9b3d563f3ee4ed32b`

Re-run the publish step and update this digest whenever `spec.yaml` changes.
