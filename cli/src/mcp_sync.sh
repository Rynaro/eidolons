#!/usr/bin/env bash
# cli/src/mcp_sync.sh — reconcile eidolons.yaml mcps: block with installed state.
#
# Usage: eidolons mcp sync
#
# Reads eidolons.yaml's optional `mcps:` block. For each declared MCP that is
# not yet installed, installs it. Idempotent: second run is a no-op.
# Does NOT upgrade already-installed MCPs (use `eidolons mcp upgrade` for that).
#
# Note: `eidolons sync` (the top-level command) does NOT call this. MCP install
# is always explicit (NG3). This command is opt-in.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp_wiring.sh"

usage() {
  cat <<EOF
eidolons mcp sync — reconcile eidolons.yaml mcps: block with installed state

Usage: eidolons mcp sync

Reads the optional 'mcps:' block from eidolons.yaml:

  mcps:
    - name: atlas-aci
      version: "^0.2.0"
    - name: junction
      version: "^0.2.0"

For each declared MCP not yet installed, installs it at the resolved version.
Idempotent: re-running when everything is already installed is a no-op.

Options:
  -h, --help  Show this help

Related:
  eidolons mcp install <name>    Install one MCP explicitly
  eidolons mcp upgrade [--all]   Upgrade installed MCPs to catalogue stable
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

if ! manifest_exists; then
  die "No eidolons.yaml found. Run 'eidolons init' first."
fi

# Read the mcps: block from eidolons.yaml (optional; may not exist).
manifest_json="$(yaml_to_json "$PROJECT_MANIFEST")"
mcps_block="$(printf '%s' "$manifest_json" | jq -r '(.mcps // []) | length')"

if [ "$mcps_block" -eq 0 ]; then
  info "eidolons.yaml has no 'mcps:' block — nothing to sync."
  info "Add a 'mcps:' section to declare MCPs, then re-run 'eidolons mcp sync'."
  exit 0
fi

say "Syncing MCPs from eidolons.yaml..."

changed=0
printf '%s' "$manifest_json" | jq -c '(.mcps // [])[]' | while IFS= read -r mentry; do
  mname="$(printf '%s' "$mentry" | jq -r '.name')"
  mver_constraint="$(printf '%s' "$mentry" | jq -r '.version // ""')"

  # Resolve constraint against catalogue stable.
  # For simplicity in v1.3: strip caret/tilde and use the literal version,
  # then check if catalogue stable satisfies the constraint.
  stable="$(mcp_catalogue_get_field "$mname" '.versions.pins.stable')"
  if [ -z "$stable" ]; then
    warn "MCP '$mname' not found in catalogue — skipping"
    continue
  fi

  # Simple caret/tilde resolution: use stable if version constraint starts with ^ or ~.
  resolved_ver="$stable"
  case "$mver_constraint" in
    ^*|~*) resolved_ver="$stable" ;;
    "")    resolved_ver="$stable" ;;
    *)     resolved_ver="${mver_constraint#v}" ;;
  esac

  # Check if already installed at resolved version.
  current="$(mcp_lock_entry "$mname" | jq -r '.version // ""')"
  if [ "$current" = "$resolved_ver" ]; then
    info "$mname@${resolved_ver} already installed — no-op"
    continue
  fi

  say "Installing $mname@${resolved_ver}..."
  bash "$SELF_DIR/mcp_install.sh" "${mname}@${resolved_ver}"
  changed=$((changed + 1))
done

if [ "$changed" -eq 0 ]; then
  ok "All declared MCPs already in sync."
else
  ok "MCP sync complete (${changed} installed)."
fi

# ─── MCP-to-Eidolon tool-surface wiring (spec §10.1) ─────────────────────────
# Re-apply wiring for all installed MCPs after the sync loop completes.
# This handles the case where per-Eidolon installers rewrote agent files.
mcp_wiring_reapply_all
