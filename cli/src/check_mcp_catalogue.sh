#!/usr/bin/env bash
# cli/src/check_mcp_catalogue.sh — CI namespace guard for the MCP catalogue.
#
# The tool namespace a host exposes (mcp__<server-key>__<tool>) derives from
# the server key registered in .mcp.json, which the nexus templates set to the
# catalogue entry's `name` verbatim. If `exposes_tools.glob` drifts from that
# key by even one byte (the historical mcp__atlas_aci__* vs mcp__atlas-aci__*
# bug), the allowlist grant is silently inert: sync injects a glob that matches
# no real tool. This script makes that failure mode impossible to merge.
#
# Checks, per roster/mcps.yaml entry:
#   1. exposes_tools.glob (when present) MUST equal  mcp__<name>__*  byte-for-byte.
#   2. Every exposes_tools.list item MUST start with  mcp__<name>__ .
#   3. install.template (when present) MUST exist and register the server under
#      the key <name> in .mcpServers — the key the glob namespace derives from.
#
# Usage:
#   bash cli/src/check_mcp_catalogue.sh [NEXUS_ROOT]
#
# NEXUS_ROOT defaults to the directory two levels above this script (i.e. the
# repo root when invoked as cli/src/check_mcp_catalogue.sh).
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

MCPS_YAML="${NEXUS_ROOT}/roster/mcps.yaml"

if [ ! -f "$MCPS_YAML" ]; then
  echo "check_mcp_catalogue: roster/mcps.yaml not found at ${MCPS_YAML}" >&2
  exit 1
fi

_mcps_json="$(yaml_to_json "$MCPS_YAML")"
_names="$(printf '%s' "$_mcps_json" | jq -r '.mcps[].name')"

if [ -z "$_names" ]; then
  echo "check_mcp_catalogue: no MCP entries found in roster/mcps.yaml" >&2
  exit 1
fi

_failures=0

_fail() {
  echo "check_mcp_catalogue: $1" >&2
  _failures=$((_failures + 1))
}

for _name in $_names; do
  _expected_glob="mcp__${_name}__*"
  _expected_prefix="mcp__${_name}__"

  # 1. glob must byte-match the namespace derived from the catalogue name.
  _glob="$(printf '%s' "$_mcps_json" \
    | jq -r --arg n "$_name" '.mcps[] | select(.name == $n) | .exposes_tools.glob // empty')"
  if [ -n "$_glob" ] && [ "$_glob" != "$_expected_glob" ]; then
    _fail "${_name}: exposes_tools.glob is '${_glob}' but the host namespace derives from the server key '${_name}' — it must be '${_expected_glob}' exactly (an off-by-one-byte glob makes every grant inert)."
  fi

  # 2. every enumerated tool must live in that namespace.
  _bad_tools="$(printf '%s' "$_mcps_json" \
    | jq -r --arg n "$_name" --arg p "$_expected_prefix" \
        '.mcps[] | select(.name == $n) | (.exposes_tools.list // [])[] | select(startswith($p) | not)')"
  if [ -n "$_bad_tools" ]; then
    while read -r _tool; do
      [ -n "$_tool" ] || continue
      _fail "${_name}: exposes_tools.list item '${_tool}' does not start with '${_expected_prefix}'."
    done <<EOF
$_bad_tools
EOF
  fi

  # 3. the template must register the server under the catalogue name, since
  #    that key is what the host turns into the mcp__<key>__* namespace.
  _template="$(printf '%s' "$_mcps_json" \
    | jq -r --arg n "$_name" '.mcps[] | select(.name == $n) | .install.template // empty')"
  if [ -n "$_template" ]; then
    if [ ! -f "${NEXUS_ROOT}/${_template}" ]; then
      _fail "${_name}: install.template '${_template}' does not exist."
    elif ! jq -e --arg n "$_name" '.mcpServers | has($n)' "${NEXUS_ROOT}/${_template}" >/dev/null 2>&1; then
      _fail "${_name}: template '${_template}' does not register a .mcpServers key named '${_name}' — the tool namespace would not match exposes_tools.glob."
    fi
  fi
done

if [ "$_failures" -gt 0 ]; then
  echo "check_mcp_catalogue: ${_failures} violation(s) — see above." >&2
  exit 1
fi

echo "check_mcp_catalogue: catalogue tool namespaces consistent — OK"
