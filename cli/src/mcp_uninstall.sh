#!/usr/bin/env bash
# cli/src/mcp_uninstall.sh — remove an MCP from this project.
#
# Usage: eidolons mcp uninstall <name> [--project-root PATH]
#
# Removes marker-bounded sections from host files and the lockfile entry.
# Idempotent: second run is a no-op.
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
eidolons mcp uninstall — remove an MCP from this project

Usage: eidolons mcp uninstall <name> [--project-root PATH]

Arguments:
  name    MCP name (see: eidolons mcp list)

Options:
  --project-root PATH  Project directory (default: cwd)
  -h, --help           Show this help

Note:
  For oci-image MCPs: the Docker image is NOT removed (may be shared with other
  projects). The .atlas/memex/codegraph.db is also preserved.
  For binary MCPs: the binary cache IS removed.
EOF
}

if [ $# -eq 0 ]; then
  usage >&2; exit 2
fi

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

mcp_name="${1:-}"
shift

project_root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      [ -z "${2:-}" ] && die "--project-root requires an argument"
      project_root="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

kind="$(mcp_resolve_kind "$mcp_name")"

case "$kind" in
  oci-image)
    if [ -n "$project_root" ]; then
      mcp_driver_oci_image_uninstall "$mcp_name" --project-root "$project_root"
    else
      mcp_driver_oci_image_uninstall "$mcp_name"
    fi
    ;;
  binary)
    mcp_driver_binary_uninstall "$mcp_name"
    ;;
  script)
    die "kind=script MCPs are not supported in v1.3"
    ;;
  *)
    die "Unknown kind '$kind' for MCP '$mcp_name'"
    ;;
esac
