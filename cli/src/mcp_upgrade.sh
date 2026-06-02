#!/usr/bin/env bash
# cli/src/mcp_upgrade.sh — upgrade installed MCPs to catalogue pins.stable.
#
# Usage: eidolons mcp upgrade [<name>|--all]
#
# Reads catalogue → resolves target version; reads lockfile → confirms current.
# Re-runs mcp_install.sh with --force only when the version has changed.
# Byte-identical lockfile on no-op upgrades (F3.4 determinism invariant).
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

usage() {
  cat <<EOF
eidolons mcp upgrade — upgrade installed MCPs to catalogue pins.stable

Usage: eidolons mcp upgrade [<name>|--all] [--no-pull]

Arguments:
  name    Upgrade a specific MCP by name.
  --all   Upgrade all installed MCPs.
          If neither is given, defaults to --all.

Options:
  --no-pull   Suppress auto-pull for oci-image MCPs during upgrade.
              If the image is missing, the upgrade aborts for that MCP.
              Accepted and ignored for kind=binary (no-op).
  -h, --help  Show this help
EOF
}

target=""
no_pull=false
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     target="--all"; shift ;;
    --no-pull) no_pull=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        warn "Unknown option: $1"; usage >&2; exit 2 ;;
    *)         target="$1"; shift ;;
  esac
done

# Default to --all when no argument given.
if [ -z "$target" ]; then
  target="--all"
fi

_upgrade_one() {
  local mname="$1"

  local stable
  stable="$(mcp_catalogue_get_field "$mname" '.versions.pins.stable')"
  if [ -z "$stable" ]; then
    warn "No stable version for $mname in catalogue — skipping"
    return 0
  fi

  local current
  current="$(mcp_lock_entry "$mname" | jq -r '.version // ""')"

  if [ -z "$current" ]; then
    say "$mname not installed — installing at ${stable}"
    if [ "$no_pull" = "true" ]; then
      bash "$SELF_DIR/mcp_install.sh" "$mname" --force --no-pull
    else
      bash "$SELF_DIR/mcp_install.sh" "$mname" --force
    fi
    return 0
  fi

  if [ "$current" = "$stable" ]; then
    info "$mname already at ${stable} — no-op"
    return 0
  fi

  say "Upgrading $mname: $current → $stable"
  if [ "$no_pull" = "true" ]; then
    bash "$SELF_DIR/mcp_install.sh" "${mname}@${stable}" --force --no-pull
  else
    bash "$SELF_DIR/mcp_install.sh" "${mname}@${stable}" --force
  fi
}

if [ "$target" = "--all" ]; then
  # Only upgrade MCPs that are already in the lockfile.
  lock_json="$(mcp_lock_read)"
  installed_names="$(printf '%s' "$lock_json" \
    | jq -r '(.mcps // [])[] | .name')"
  if [ -z "$installed_names" ]; then
    info "No MCPs installed — nothing to upgrade."
    exit 0
  fi
  while IFS= read -r mname; do
    [ -z "$mname" ] && continue
    _upgrade_one "$mname"
  done <<< "$installed_names"
else
  # Validate.
  kind="$(mcp_resolve_kind "$target")" || exit 1
  _upgrade_one "$target"
fi

ok "Upgrade complete."
