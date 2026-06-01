#!/usr/bin/env bash
# cli/src/stage_mcp_digest.sh — resolve a published OCI image's index digest and
# pin it into roster/mcps.yaml, replacing the __PENDING_<version>_DIGEST__ sentinel.
#
# Use after an MCP's image has been published to its registry (e.g. once the
# CRYSTALIUM release.yml workflow has pushed ghcr.io/rynaro/crystalium:<version>).
#
# Usage:
#   bash cli/src/stage_mcp_digest.sh <mcp-name> <version> [NEXUS_ROOT]
#   bash cli/src/stage_mcp_digest.sh crystalium 1.2.0
#
# What it does:
#   1. Reads source.image for <mcp-name> from roster/mcps.yaml.
#   2. Resolves the published multi-arch index digest via
#      `docker buildx imagetools inspect <image>:<version> --format '{{.Manifest.Digest}}'`
#      (validated against the known-good 0.1.0 index digest at build time).
#   3. Validates the result is a sha256 digest.
#   4. Replaces the __PENDING_<version-underscored>_DIGEST__ sentinel in mcps.yaml.
#   5. Re-runs the roster skew guard.
#
# Idempotent: if the sentinel is already gone and the pinned digest already
# matches the published one, it reports OK and makes no change.
#
# Requires: docker (buildx), yq (via yaml_to_json), jq.
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cli/src/lib.sh
. "$SELF_DIR/lib.sh"

MCP_NAME="${1:-}"
VERSION="${2:-}"
NEXUS_ROOT="${3:-"$(cd "$SELF_DIR/../.." && pwd)"}"

if [ -z "$MCP_NAME" ] || [ -z "$VERSION" ]; then
  die "usage: stage_mcp_digest.sh <mcp-name> <version> [NEXUS_ROOT]"
fi

MCPS_YAML="${NEXUS_ROOT}/roster/mcps.yaml"
[ -f "$MCPS_YAML" ] || die "roster/mcps.yaml not found at ${MCPS_YAML}"
command -v docker >/dev/null 2>&1 || die "docker is required to resolve the image digest"

# Sentinel token: dots → underscores (1.2.0 → __PENDING_1_2_0_DIGEST__).
_ver_us="$(printf '%s' "$VERSION" | tr '.' '_')"
SENTINEL="__PENDING_${_ver_us}_DIGEST__"

# Resolve source.image for this mcp from the catalogue.
_image="$(yaml_to_json "$MCPS_YAML" \
  | jq -r --arg n "$MCP_NAME" '.mcps[] | select(.name == $n) | .source.image // empty')"
[ -n "$_image" ] || die "no source.image for mcp '${MCP_NAME}' in roster/mcps.yaml"

_ref="${_image}:${VERSION}"
say "resolving index digest for ${_ref} ..."

_digest="$(docker buildx imagetools inspect "$_ref" --format '{{.Manifest.Digest}}' 2>/dev/null || true)"
if [ -z "$_digest" ]; then
  die "could not resolve a digest for ${_ref} — is the image published to the registry yet?"
fi

# Validate sha256:<64 hex>.
case "$_digest" in
  sha256:*) ;;
  *) die "resolved digest is not a sha256 reference: ${_digest}" ;;
esac
_hex="${_digest#sha256:}"
if [ "${#_hex}" -ne 64 ]; then
  die "resolved digest has unexpected length: ${_digest}"
fi

# Current pinned value for this version (may be the sentinel or a real digest).
_current="$(yaml_to_json "$MCPS_YAML" \
  | jq -r --arg n "$MCP_NAME" --arg v "$VERSION" \
      '.mcps[] | select(.name == $n) | .versions.releases[$v].digest // empty')"

if [ "$_current" = "$_digest" ]; then
  ok "${MCP_NAME} ${VERSION} digest already pinned to ${_digest} — no change"
  exit 0
fi

if [ "$_current" != "$SENTINEL" ] && [ -n "$_current" ]; then
  warn "${MCP_NAME} ${VERSION} already pins a non-sentinel digest (${_current}) that differs from the published one (${_digest})."
  die "refusing to overwrite a real digest automatically — investigate the mismatch and edit by hand."
fi

# Swap the sentinel for the resolved digest. Surgical: the sentinel token is unique.
if ! grep -q "$SENTINEL" "$MCPS_YAML"; then
  die "sentinel ${SENTINEL} not found in roster/mcps.yaml — nothing to stage."
fi

_tmp="$(mktemp)"
sed "s|${SENTINEL}|${_digest}|g" "$MCPS_YAML" > "$_tmp"
mv "$_tmp" "$MCPS_YAML"
ok "pinned ${MCP_NAME} ${VERSION} → ${_digest}"

# Re-validate roster parity.
if [ -f "${SELF_DIR}/check_roster_mcp_skew.sh" ]; then
  bash "${SELF_DIR}/check_roster_mcp_skew.sh" "$NEXUS_ROOT"
fi

# Belt-and-braces: confirm no sentinel survives.
if grep -q "__PENDING_.*_DIGEST__" "$MCPS_YAML"; then
  warn "a __PENDING_*_DIGEST__ sentinel still remains in roster/mcps.yaml — other versions may be unstaged."
fi
