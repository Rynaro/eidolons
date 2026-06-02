#!/usr/bin/env bash
# cli/src/mcp_refresh.sh — re-fetch an MCP artefact without touching host wiring.
#
# Usage: eidolons mcp refresh <name> [--image-digest DIGEST]
#
# For oci-image: re-pull the image at the locked digest.
# For binary: re-run the install.sh fetch at the locked version.
# Does NOT regenerate .mcp.json or other host wiring files.
# Updates installed_at in the lockfile (refresh is a "touch").
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
eidolons mcp refresh — re-fetch an MCP artefact (image pull / binary re-download)

Usage: eidolons mcp refresh <name> [--image-digest DIGEST]

Arguments:
  name    MCP name (see: eidolons mcp list)

Options:
  --image-digest DIGEST  Override the digest to pull (oci-image only)
  -h, --help             Show this help
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

image_digest=""
while [ $# -gt 0 ]; do
  case "$1" in
    --image-digest)
      [ -z "${2:-}" ] && die "--image-digest requires an argument"
      image_digest="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

kind="$(mcp_resolve_kind "$mcp_name")"
locked_ver="$(mcp_lock_entry "$mcp_name" | jq -r '.version // empty')"
if [ -z "$locked_ver" ]; then
  locked_ver="$(mcp_resolve_version "$mcp_name" "")"
fi

say "Refreshing ${mcp_name}@${locked_ver} (kind=${kind})"

case "$kind" in
  oci-image)
    if [ -n "$image_digest" ]; then
      # Override-digest path: route through the generic pull driver (MCP-agnostic).
      # Previously hardcoded to mcp_atlas_aci_pull.sh — now works for any oci-image MCP.
      mcp_driver_oci_image_pull "$mcp_name" --image-digest "$image_digest"
      # Update installed_at in lock.
      local_entry="$(mcp_lock_entry "$mcp_name")"
      if [ -n "$local_entry" ]; then
        new_ts="$(_mcp_now)"
        new_arr="$(mcp_lock_read | jq '(.mcps // [])')"
        updated="$(printf '%s' "$local_entry" | jq --arg ts "$new_ts" '.installed_at = $ts')"
        new_arr="$(printf '%s' "$new_arr" \
          | jq --arg n "$mcp_name" 'map(select(.name != $n))')"
        new_arr="$(printf '%s' "$new_arr" | jq --argjson e "$updated" '. + [$e]')"
        mcp_lock_write_from_array "$new_arr"
      fi
    else
      mcp_driver_oci_image_refresh "$mcp_name" "$locked_ver"
    fi
    ;;
  binary)
    mcp_driver_binary_refresh "$mcp_name" "$locked_ver"
    ;;
  script)
    die "kind=script MCPs are not supported in v1.3"
    ;;
  *)
    die "Unknown kind '$kind' for MCP '$mcp_name'"
    ;;
esac

# ─── MCP-to-Eidolon tool-surface wiring (spec §10.1) ─────────────────────────
# Apply after the per-kind driver returns success (refresh = re-wire to handle
# any per-Eidolon installer rewrite that may have happened between installs).
mcp_wiring_apply_for_mcp "$mcp_name"
