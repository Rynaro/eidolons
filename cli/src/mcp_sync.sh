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

# _mcp_sync_version_satisfies VERSION CONSTRAINT
# Supports the manifest forms documented by this command: exact, ^ and ~.
# Prereleases must be requested exactly; they are never selected by a range.
_mcp_sync_version_satisfies() {
  local version="${1#v}" constraint="${2:-}"
  [ -z "$constraint" ] && return 0
  local op="exact" requested="$constraint"
  case "$requested" in
    ^*) op="caret"; requested="${requested#^}" ;;
    ~*) op="tilde"; requested="${requested#~}" ;;
  esac
  requested="${requested#v}"
  [ "$op" = "exact" ] && [ "$version" = "$requested" ] && return 0
  case "$version:$requested" in
    *-*:*) return 1 ;;
  esac
  local vmaj vmin vpatch rmaj rmin rpatch
  IFS=. read -r vmaj vmin vpatch <<EOF
$version
EOF
  IFS=. read -r rmaj rmin rpatch <<EOF
$requested
EOF
  case "$vmaj$vmin$vpatch$rmaj$rmin$rpatch" in *[!0-9]*) return 1 ;; esac
  case "$op" in
    caret)
      if [ "$rmaj" -gt 0 ]; then
        [ "$vmaj" -eq "$rmaj" ] && [ "$vmin" -ge "$rmin" ] || return 1
        [ "$vmin" -gt "$rmin" ] || [ "$vpatch" -ge "$rpatch" ]
      elif [ "$rmin" -gt 0 ]; then
        [ "$vmaj" -eq 0 ] && [ "$vmin" -eq "$rmin" ] && [ "$vpatch" -ge "$rpatch" ]
      else
        [ "$vmaj" -eq 0 ] && [ "$vmin" -eq 0 ] && [ "$vpatch" -eq "$rpatch" ]
      fi
      ;;
    tilde)
      [ "$vmaj" -eq "$rmaj" ] && [ "$vmin" -eq "$rmin" ] && [ "$vpatch" -ge "$rpatch" ]
      ;;
  esac
}

# _mcp_sync_config_present NAME VERSION — a same-version MCP is only in sync
# when its project registration matches the rendered configuration. Presence
# alone cannot detect stale UID pins, bind mounts, resource flags, or image argv.
_mcp_sync_config_present() {
  local name="$1" version="$2" kind
  kind="$(mcp_catalogue_get_field "$name" '.kind')"
  if [ "$kind" = "oci-image" ]; then
    _mcp_oci_config_is_current "$name" "$version" "$(pwd)"
    return $?
  fi
  if [ "$kind" = "binary" ]; then
    local selected
    selected="$(mcp_lock_entry "$name" | jq -r '.target // empty')"
    [ -n "$selected" ] || return 1
    _mcp_binary_confirm_wired "$name" "$(pwd)" "$selected" || return 1
  fi
  local file
  for file in .mcp.json .cursor/mcp.json; do
    [ -f "$file" ] || continue
    jq -e --arg n "$name" '.mcpServers[$n] != null' "$file" >/dev/null 2>&1 && return 0
  done
  [ -f .codex/config.toml ] && grep -q "^\[mcp_servers\.${name}\]$" .codex/config.toml 2>/dev/null && return 0
  [ -f .opencode/opencode.json ] && jq -e --arg n "$name" '.mcp[$n] != null' .opencode/opencode.json >/dev/null 2>&1 && return 0
  return 1
}

changed=0
entries_file="$(mktemp)"
printf '%s' "$manifest_json" | jq -c '(.mcps // [])[]' > "$entries_file"
while IFS= read -r mentry; do
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
  mkind="$(mcp_catalogue_get_field "$mname" '.kind')"
  entry_profile="$(printf '%s' "$mentry" | jq -r '.resource_profile // empty')"
  if [ -n "$entry_profile" ] && [ "$mkind" != "oci-image" ]; then
    die "MCP '$mname' is kind=${mkind}; resource_profile is valid only for OCI MCPs"
  fi

  # `mcp sync` reconciles a declared constraint; it is not an upgrade command.
  # A currently installed version that already satisfies the constraint must
  # remain selected even when the catalogue stable pin advances.  Still repair
  # a missing host registration or stale OCI runtime receipt at that version.
  current="$(mcp_lock_entry "$mname" | jq -r '.version // ""')"
  if [ -n "$current" ] && _mcp_sync_version_satisfies "$current" "$mver_constraint"; then
    if _mcp_sync_config_present "$mname" "$current" && { [ "$mkind" != "oci-image" ] || _mcp_runtime_is_current "$mname" "$(pwd)"; }; then
      info "$mname@${current} already installed — no-op"
      continue
    fi
    say "Repairing $mname@${current} project registration..."
    bash "$SELF_DIR/mcp_install.sh" "${mname}@${current}" --force
    changed=$((changed + 1))
    continue
  fi

  # Prefer stable only when it satisfies the declared range. If it does not,
  # choose the highest compatible catalogue release rather than silently
  # crossing a compatibility boundary.
  resolved_ver="$stable"
  if ! _mcp_sync_version_satisfies "$stable" "$mver_constraint"; then
    resolved_ver="$(mcp_catalogue_get "$mname" | jq -r '.versions.releases | keys[]' 2>/dev/null \
      | while IFS= read -r candidate; do
          # Do not let a non-matching final release terminate this pipe under
          # `set -e -o pipefail`; no match is handled below as a normal error.
          if _mcp_sync_version_satisfies "$candidate" "$mver_constraint"; then
            printf '%s\n' "$candidate"
          fi
        done \
      | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
    [ -n "$resolved_ver" ] || die "MCP '$mname' has no release satisfying '$mver_constraint'"
  fi

  # Check version and the resolved OCI runtime receipt. A profile or catalogue
  # limit change at the same image version still requires regeneration.
  if [ "$current" = "$resolved_ver" ]; then
    if _mcp_sync_config_present "$mname" "$resolved_ver" && { [ "$mkind" != "oci-image" ] || _mcp_runtime_is_current "$mname" "$(pwd)"; }; then
      info "$mname@${resolved_ver} already installed — no-op"
      continue
    fi
    say "Repairing $mname@${resolved_ver} project registration..."
    bash "$SELF_DIR/mcp_install.sh" "${mname}@${resolved_ver}" --force
    changed=$((changed + 1))
    continue
  fi

  say "Installing $mname@${resolved_ver}..."
  # A declared constraint can deliberately move an already-installed MCP to
  # another compatible release. The driver otherwise protects an existing
  # entry, so make this reconciliation explicit and preserve its receipt.
  if [ -n "$current" ]; then
    bash "$SELF_DIR/mcp_install.sh" "${mname}@${resolved_ver}" --force
  else
    bash "$SELF_DIR/mcp_install.sh" "${mname}@${resolved_ver}"
  fi
  changed=$((changed + 1))
done < "$entries_file"
rm -f "$entries_file"

if [ "$changed" -eq 0 ]; then
  ok "All declared MCPs already in sync."
else
  ok "MCP sync complete (${changed} installed)."
fi

# ─── MCP-to-Eidolon tool-surface wiring (spec §10.1) ─────────────────────────
# Re-apply wiring for all installed MCPs after the sync loop completes.
# This handles the case where per-Eidolon installers rewrote agent files.
mcp_wiring_reapply_all
