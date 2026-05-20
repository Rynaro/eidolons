#!/usr/bin/env bash
# cli/src/mcp_health.sh — run health probes for installed MCPs.
#
# Usage: eidolons mcp health [<name>|--all]
#
# Output format: "<name>  <probe>  ok|degraded|missing  [reason]"
# Exit code is always 0 (health is a probe verb; status line is the signal).
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
eidolons mcp health — run health probes for installed MCPs

Usage: eidolons mcp health [<name>|--all]

Arguments:
  name    Run health probes for a specific MCP.
  --all   Run health probes for all installed MCPs (default if no arg).

Options:
  -h, --help  Show this help

Exit code: always 0. The status lines on stdout are the signal:
  ok        All probes passed.
  degraded  Some probes failed but the MCP may partially work.
  missing   MCP not installed or critical dependency absent.
EOF
}

target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     target="--all"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        warn "Unknown option: $1"; usage >&2; exit 2 ;;
    *)         target="$1"; shift ;;
  esac
done

if [ -z "$target" ]; then
  target="--all"
fi

_health_one() {
  local mname="$1"

  # Check if installed.
  local lock_entry
  lock_entry="$(mcp_lock_entry "$mname")"
  if [ -z "$lock_entry" ]; then
    printf '%s  OVERALL  not-installed  run: eidolons mcp install %s\n' "$mname" "$mname"
    return 0
  fi

  local kind
  kind="$(mcp_resolve_kind "$mname")"

  case "$kind" in
    oci-image) mcp_driver_oci_image_health "$mname" ;;
    binary)    mcp_driver_binary_health    "$mname" ;;
    *)
      printf '%s  OVERALL  degraded  unsupported kind: %s\n' "$mname" "$kind"
      ;;
  esac
}

if [ "$target" = "--all" ]; then
  lock_json="$(mcp_lock_read)"
  installed_names="$(printf '%s' "$lock_json" \
    | jq -r '(.mcps // [])[] | .name')"
  if [ -z "$installed_names" ]; then
    info "No MCPs installed — nothing to probe."
    info "Run 'eidolons mcp list' to see the catalogue."
    exit 0
  fi
  while IFS= read -r mname; do
    [ -z "$mname" ] && continue
    _health_one "$mname"
    echo ""
  done <<< "$installed_names"
else
  # Validate it's in the catalogue.
  _cat_entry="$(mcp_catalogue_get "$target")"
  if [ -z "$_cat_entry" ]; then
    printf "MCP '%s' not found in catalogue. Try: eidolons mcp list\n" "$target" >&2
    exit 1
  fi
  unset _cat_entry
  _health_one "$target"
fi

exit 0
