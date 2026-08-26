#!/usr/bin/env bash
# Publish the gitguardian kit artifacts to Docker Hub.
#
# One repo, one tag per coding agent:
#   docker.io/<ns>/gitguardian-kit:claude
#   docker.io/<ns>/gitguardian-kit:codex
#   docker.io/<ns>/gitguardian-kit:copilot
#   docker.io/<ns>/gitguardian-kit:cursor
#   docker.io/<ns>/gitguardian-kit:latest   (alias of :claude, same digest)
#
# Consumers pin by DIGEST (sbx rejects OCI tags at consume time), so the tag is
# just a human-facing label that points at the digest to copy.
#
# Usage:
#   ./scripts/publish.sh                 # publish ALL agent tags to docker.io/ajeetraina777/gitguardian-kit
#   ./scripts/publish.sh <namespace>     # publish ALL agent tags under <namespace>
#   ./scripts/publish.sh <namespace> <agent>   # publish only one agent tag (claude|codex|copilot|cursor)
#
# Requires: `sbx` (a RELEASE build) on PATH and `docker login` already done
# (sbx kit push uses the Docker credential store). The kit is a kind: mixin, so
# this pushes the OCI *artifact* (spec.yaml + files) - no container image.
set -euo pipefail

NAMESPACE="${1:-ajeetraina777}"
ONLY_AGENT="${2:-}"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_LAYER_MEDIA_TYPE="application/vnd.oci.image.layer.v1.tar+gzip"
REPO_NAME="gitguardian-kit"

# agent | kit source dir (relative to repo root) | OCI tag
AGENTS=(
  "claude|.|claude"
  "codex|kits/codex|codex"
  "copilot|kits/copilot|copilot"
  "cursor|kits/cursor|cursor"
)

echo ">> Ensuring generated specs are up to date"
"${KIT_DIR}/scripts/gen-kits.sh" --check || {
  echo "ERROR: specs are stale. Run ./scripts/gen-kits.sh and commit." >&2
  exit 1
}

REPO="docker.io/${NAMESPACE}/${REPO_NAME}"
declare -a SUMMARY
CLAUDE_DIGEST=""

publish_one() {
  local agent="$1" src="$2" tag="$3"
  local dir="${KIT_DIR}/${src}" ref="${REPO}:${tag}"

  echo
  echo "==================================================================="
  echo ">> [${agent}] validating ${dir}"
  sbx kit validate "${dir}"

  echo ">> [${agent}] pushing ${ref}"
  sbx kit push "${dir}" "${ref}"

  echo ">> [${agent}] verifying pushed artifact"
  local manifest
  manifest="$(docker buildx imagetools inspect --raw "${ref}")"
  if ! grep -qF "${KIT_LAYER_MEDIA_TYPE}" <<<"${manifest}"; then
    echo >&2
    echo "ERROR: ${ref} has no ${KIT_LAYER_MEDIA_TYPE} layer." >&2
    echo "       Released sbx clients cannot resolve this artifact." >&2
    echo "       'sbx version' is probably a dev build; re-push from a release" >&2
    echo "       build. See PUBLISHING.md." >&2
    exit 1
  fi

  local digest
  digest="$(docker buildx imagetools inspect "${ref}" | awk '/^Digest:/ { print $2; exit }')"
  echo ">> [${agent}] OK  ${ref}  digest: ${digest}"
  [ "$agent" = "claude" ] && CLAUDE_DIGEST="$digest"
  SUMMARY+=("${agent}|${tag}|${digest}")
}

for row in "${AGENTS[@]}"; do
  IFS='|' read -r agent src tag <<<"$row"
  [ -n "$ONLY_AGENT" ] && [ "$ONLY_AGENT" != "$agent" ] && continue
  publish_one "$agent" "$src" "$tag"
done

# Also publish claude to :latest as the sensible default tag. We re-push (rather
# than retag) because Docker Hub push needs credentialed auth and `docker buildx
# imagetools create` mangles OCI *artifact* manifests. :latest therefore carries
# the same claude spec as :claude but a distinct digest (the created-timestamp
# annotation differs) - harmless, since consumers pin the :claude digest.
if [ -z "$ONLY_AGENT" ] || [ "$ONLY_AGENT" = "claude" ]; then
  echo
  echo ">> publishing ${REPO}:latest (= claude default)"
  sbx kit push "${KIT_DIR}/." "${REPO}:latest"
  LATEST_DIGEST="$(docker buildx imagetools inspect "${REPO}:latest" | awk '/^Digest:/ { print $2; exit }')"
  echo ">> :latest digest: ${LATEST_DIGEST}"
fi

echo
echo "==================================================================="
echo ">> Published to ${REPO} (pin these digests in README.md / PUBLISHING.md):"
echo
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r agent tag digest <<<"$row"
  printf "   %-8s :%-8s %s\n" "$agent" "$tag" "$digest"
done
echo
echo ">> Consume, e.g.:"
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r agent tag digest <<<"$row"
  printf "   sbx run %s --kit \"oci://%s@%s\" .\n" "$agent" "$REPO" "$digest"
done
