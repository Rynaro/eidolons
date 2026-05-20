#!/usr/bin/env bash
# cli/src/mcp_install.sh — install an MCP (kind-switch driver).
#
# Usage: eidolons mcp install <name>[@<ver>] [--force] [--project-root PATH]
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
eidolons mcp install — install an MCP into this project

Usage: eidolons mcp install <name>[@<ver>] [--force] [--project-root PATH]

Arguments:
  name[@ver]    MCP name, optionally with version (e.g. atlas-aci@0.2.2).
                Defaults to catalogue pins.stable when version is omitted.

Options:
  --force              Reinstall even if already at the requested version.
  --project-root PATH  Project directory to install into (default: cwd).
  -h, --help           Show this help.

Examples:
  eidolons mcp install atlas-aci
  eidolons mcp install junction@0.2.0
  eidolons mcp install atlas-aci --force
EOF
}

if [ $# -eq 0 ]; then
  usage >&2
  exit 2
fi

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

name_ver="${1:-}"
shift

force=false
project_root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force)         force=true; shift ;;
    --project-root)
      [ -z "${2:-}" ] && die "--project-root requires an argument"
      project_root="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

# Parse name[@version].
case "$name_ver" in
  *@*)
    mcp_name="${name_ver%%@*}"
    mcp_ver="${name_ver#*@}"
    ;;
  *)
    mcp_name="$name_ver"
    mcp_ver=""
    ;;
esac

# Validate catalogue entry.
kind="$(mcp_resolve_kind "$mcp_name")"

# Resolve version.
mcp_ver="$(mcp_resolve_version "$mcp_name" "$mcp_ver")"

say "Installing ${mcp_name}@${mcp_ver} (kind=${kind})"

case "$kind" in
  oci-image)
    if [ "$force" = "true" ]; then
      mcp_driver_oci_image_install "$mcp_name" "$mcp_ver" --force \
        ${project_root:+--project-root "$project_root"}
    else
      mcp_driver_oci_image_install "$mcp_name" "$mcp_ver" \
        ${project_root:+--project-root "$project_root"}
    fi
    ;;
  binary)
    if [ "$force" = "true" ]; then
      mcp_driver_binary_install "$mcp_name" "$mcp_ver" --force
    else
      mcp_driver_binary_install "$mcp_name" "$mcp_ver"
    fi
    ;;
  script)
    die "kind=script MCPs are not supported in v1.3 (NG6)"
    ;;
  *)
    die "Unknown kind '$kind' for MCP '$mcp_name'"
    ;;
esac
