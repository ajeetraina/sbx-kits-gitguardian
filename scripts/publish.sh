#!/usr/bin/env bash
# Publish the gitguardian kit artifact to a Docker Hub (or any OCI) registry.
#
# Usage:
#   ./scripts/publish.sh                 # pushes docker.io/ajeetraina777/gitguardian-kit:latest
#   ./scripts/publish.sh <namespace>     # pushes docker.io/<namespace>/gitguardian-kit:latest
#   ./scripts/publish.sh <namespace> <tag>
#
# Requires: `sbx` on PATH and `docker login` already done (sbx kit push uses
# the Docker credential store). The kit is a kind: mixin, so this pushes the
# OCI *artifact* (spec.yaml + files) - no container image is built.
set -euo pipefail

NAMESPACE="${1:-ajeetraina777}"
TAG="${2:-latest}"
REF="docker.io/${NAMESPACE}/gitguardian-kit:${TAG}"

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KIT_LAYER_MEDIA_TYPE="application/vnd.oci.image.layer.v1.tar+gzip"

echo ">> Validating kit at ${KIT_DIR}"
sbx kit validate "${KIT_DIR}/"

echo ">> Pushing ${REF}"
sbx kit push "${KIT_DIR}/" "${REF}"

# A development build of sbx writes the kit layer as
# application/vnd.oci.empty.v1+json instead of a tar+gzip layer. The push still
# reports success, but no released sbx can resolve the result:
#   ERROR: resolve kits: no v2 kit layer found in manifest
# Catch that here rather than letting consumers discover it. See PUBLISHING.md.
echo ">> Verifying pushed artifact"
MANIFEST="$(docker buildx imagetools inspect --raw "${REF}")"
if ! grep -qF "${KIT_LAYER_MEDIA_TYPE}" <<<"${MANIFEST}"; then
  echo >&2
  echo "ERROR: ${REF} has no ${KIT_LAYER_MEDIA_TYPE} layer." >&2
  echo "       Released sbx clients cannot resolve this artifact." >&2
  echo "       'sbx version' is probably a dev build (a -<n>-g<sha> suffix);" >&2
  echo "       re-push from a release build. See PUBLISHING.md." >&2
  echo >&2
  echo "Manifest layers:" >&2
  grep -o '"mediaType": "[^"]*"' <<<"${MANIFEST}" >&2
  exit 1
fi

DIGEST="$(docker buildx imagetools inspect "${REF}" | awk '/^Digest:/ { print $2; exit }')"

echo ">> OK: tar+gzip kit layer present"
echo
echo ">> Published ${REF}"
echo "   digest: ${DIGEST}"
echo
echo ">> Consume it with:"
echo "   sbx run claude --kit \"oci://${REF%:*}@${DIGEST}\" ."
echo
echo ">> Update the digest in README.md and PUBLISHING.md to match."
