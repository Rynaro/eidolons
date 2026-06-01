#!/usr/bin/env bash
# cli/src/check_roster_mcp_skew.sh — CI skew guard for crystalium version parity.
#
# Fails (exit 1) if the crystalium versions.latest in roster/mcps.yaml and
# roster/index.yaml do not match.
#
# Usage:
#   bash cli/src/check_roster_mcp_skew.sh [NEXUS_ROOT]
#
# NEXUS_ROOT defaults to the directory two levels above this script (i.e. the
# repo root when invoked as cli/src/check_roster_mcp_skew.sh).
#
# Requires: yq (mikefarah Go or compatible), jq
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXUS_ROOT="${1:-"$(cd "$SELF_DIR/../.." && pwd)"}"

# Reuse the canonical yaml_to_json helper (handles mikefarah/kislyuk yq + the
# python3 fallback). yq eval '.' alone emits YAML, not JSON, which jq cannot parse.
# shellcheck source=cli/src/lib.sh
. "$SELF_DIR/lib.sh"

INDEX_YAML="${NEXUS_ROOT}/roster/index.yaml"
MCPS_YAML="${NEXUS_ROOT}/roster/mcps.yaml"

if [ ! -f "$INDEX_YAML" ]; then
  echo "check_roster_mcp_skew: roster/index.yaml not found at ${INDEX_YAML}" >&2
  exit 1
fi

if [ ! -f "$MCPS_YAML" ]; then
  echo "check_roster_mcp_skew: roster/mcps.yaml not found at ${MCPS_YAML}" >&2
  exit 1
fi

# Extract crystalium versions.latest from each file. yaml_to_json emits JSON on
# stdout (yq/python under the hood); jq then queries it.
_index_ver="$(yaml_to_json "$INDEX_YAML" \
  | jq -r '.eidolons[] | select(.name == "crystalium") | .versions.latest // empty')"

_mcps_ver="$(yaml_to_json "$MCPS_YAML" \
  | jq -r '.mcps[] | select(.name == "crystalium") | .versions.latest // empty')"

if [ -z "$_index_ver" ]; then
  echo "check_roster_mcp_skew: crystalium not found in roster/index.yaml" >&2
  exit 1
fi

if [ -z "$_mcps_ver" ]; then
  echo "check_roster_mcp_skew: crystalium not found in roster/mcps.yaml" >&2
  exit 1
fi

if [ "$_index_ver" != "$_mcps_ver" ]; then
  echo "check_roster_mcp_skew: crystalium version skew detected:" >&2
  echo "  roster/index.yaml  versions.latest = ${_index_ver}" >&2
  echo "  roster/mcps.yaml   versions.latest = ${_mcps_ver}" >&2
  echo "Both files must be bumped together when releasing a new crystalium version." >&2
  exit 1
fi

echo "check_roster_mcp_skew: crystalium versions match (${_index_ver}) — OK"
