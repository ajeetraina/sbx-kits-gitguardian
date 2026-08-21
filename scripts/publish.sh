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

echo ">> Validating kit at ${KIT_DIR}"
sbx kit validate "${KIT_DIR}/"

echo ">> Pushing ${REF}"
sbx kit push "${KIT_DIR}/" "${REF}"

echo
echo ">> Published. Resolve the digest consumers should pin with:"
echo "   docker buildx imagetools inspect ${REF} | grep -i digest"
echo
echo ">> Consume it with:"
echo "   sbx run claude --kit \"oci://${REF%:*}@sha256:<digest>\" ."
