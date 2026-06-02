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
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp_wiring.sh"

usage() {
  cat <<EOF
eidolons mcp install — install an MCP into this project

Usage: eidolons mcp install <name>[@<ver>] [--force] [--project-root PATH] [--no-pull]

Arguments:
  name[@ver]    MCP name, optionally with version (e.g. atlas-aci@0.2.2).
                Defaults to catalogue pins.stable when version is omitted.

Options:
  --force              Reinstall even if already at the requested version.
  --project-root PATH  Project directory to install into (default: cwd).
  --no-pull            Suppress auto-pull for oci-image MCPs. If the image is
                       missing, install aborts with a name-aware message.
                       Accepted and ignored for kind=binary (no-op).
  -h, --help           Show this help.

Examples:
  eidolons mcp install atlas-aci
  eidolons mcp install junction@0.2.0
  eidolons mcp install atlas-aci --force
  eidolons mcp install crystalium --no-pull
EOF
}

# Refresh the nexus roster data before resolving version/kind so that
# catalogue bumps on the channel ref are picked up automatically (STORY-6).
# Inherits all skip-guards (EIDOLONS_NEXUS / EIDOLONS_SKIP_REFRESH) and is
# non-fatal on network failure.
nexus_refresh

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
no_pull=false
while [ $# -gt 0 ]; do
  case "$1" in
    --force)         force=true; shift ;;
    --project-root)
      [ -z "${2:-}" ] && die "--project-root requires an argument"
      project_root="$2"
      shift 2
      ;;
    --no-pull)       no_pull=true; shift ;;
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
    if [ "$force" = "true" ] && [ "$no_pull" = "true" ]; then
      mcp_driver_oci_image_install "$mcp_name" "$mcp_ver" --force --no-pull \
        ${project_root:+--project-root "$project_root"}
    elif [ "$force" = "true" ]; then
      mcp_driver_oci_image_install "$mcp_name" "$mcp_ver" --force \
        ${project_root:+--project-root "$project_root"}
    elif [ "$no_pull" = "true" ]; then
      mcp_driver_oci_image_install "$mcp_name" "$mcp_ver" --no-pull \
        ${project_root:+--project-root "$project_root"}
    else
      mcp_driver_oci_image_install "$mcp_name" "$mcp_ver" \
        ${project_root:+--project-root "$project_root"}
    fi
    ;;
  binary)
    # --no-pull is accepted and ignored for kind=binary (no OCI concept here).
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

# ─── MCP-to-Eidolon tool-surface wiring (spec §10.1) ─────────────────────────
# Apply after the per-kind driver returns success.
# Soft failure: mcp_wiring_apply_for_mcp warns on individual file errors but
# never aborts the parent command (see spec §10.4).
mcp_wiring_apply_for_mcp "$mcp_name"
