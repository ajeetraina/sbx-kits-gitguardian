#!/usr/bin/env bash
# Publish the gitguardian kit artifacts (one per coding agent) to Docker Hub.
#
# Usage:
#   ./scripts/publish.sh                 # publish ALL agents to docker.io/ajeetraina777/...
#   ./scripts/publish.sh <namespace>     # publish ALL agents under <namespace>
#   ./scripts/publish.sh <namespace> <agent>   # publish only one agent (claude|codex|copilot|cursor)
#
# Requires: `sbx` (a RELEASE build) on PATH and `docker login` already done
# (sbx kit push uses the Docker credential store). The kit is a kind: mixin, so
# this pushes the OCI *artifact* (spec.yaml + files) - no container image.
#
# Artifact naming: claude is the default artifact (gitguardian-kit); the others
# get an -<agent> suffix (gitguardian-kit-codex, ...).
set -euo pipefail

NAMESPACE="${1:-ajeetraina777}"
ONLY_AGENT="${2:-}"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_LAYER_MEDIA_TYPE="application/vnd.oci.image.layer.v1.tar+gzip"

# agent | kit source dir (relative to repo root) | OCI repo name
AGENTS=(
  "claude|.|gitguardian-kit"
  "codex|kits/codex|gitguardian-kit-codex"
  "copilot|kits/copilot|gitguardian-kit-copilot"
  "cursor|kits/cursor|gitguardian-kit-cursor"
)

echo ">> Ensuring generated specs are up to date"
"${KIT_DIR}/scripts/gen-kits.sh" --check || {
  echo "ERROR: specs are stale. Run ./scripts/gen-kits.sh and commit." >&2
  exit 1
}

declare -a SUMMARY

publish_one() {
  local agent="$1" src="$2" repo="$3"
  local dir="${KIT_DIR}/${src}" ref="docker.io/${NAMESPACE}/${repo}:latest"

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
  echo ">> [${agent}] OK  digest: ${digest}"
  SUMMARY+=("${agent}|${ref%:*}|${digest}")
}

for row in "${AGENTS[@]}"; do
  IFS='|' read -r agent src repo <<<"$row"
  [ -n "$ONLY_AGENT" ] && [ "$ONLY_AGENT" != "$agent" ] && continue
  publish_one "$agent" "$src" "$repo"
done

echo
echo "==================================================================="
echo ">> Published artifacts (pin these digests in README.md / PUBLISHING.md):"
echo
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r agent repo digest <<<"$row"
  printf "   %-8s %s@%s\n" "$agent" "$repo" "$digest"
done
echo
echo ">> Consume, e.g.:"
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r agent repo digest <<<"$row"
  printf "   sbx run %s --kit \"oci://%s@%s\" .\n" "$agent" "$repo" "$digest"
done
