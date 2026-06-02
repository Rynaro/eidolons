#!/usr/bin/env bash
# cli/src/mcp_pull.sh — generic OCI image pull for 'eidolons mcp pull <name>'.
#
# Usage: eidolons mcp pull <name> [--image-digest DIGEST] [--build-locally] [--git-ref REF]
#
# Validates that <name> is a kind=oci-image MCP, then delegates to
# mcp_driver_oci_image_pull in lib_mcp.sh. Catalogue-pin driven; does NOT touch
# the lockfile or .mcp.json.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

usage() {
  cat >&2 <<EOF
eidolons mcp pull — pull an OCI image MCP onto this host

Usage: eidolons mcp pull <name> [OPTIONS]

Arguments:
  name                   MCP name (kind=oci-image; see: eidolons mcp list)

Options:
  --image-digest DIGEST  Override the catalogue-pinned digest (sha256:...).
  --build-locally        Build the image locally from source instead of
                         pulling from the registry. ONLY valid for MCPs that
                         declare a buildable source. Errors with exit 2 for
                         pull-only MCPs.
  --git-ref REF          Git ref to build from when --build-locally is used
                         (default: the MCP's declared build_ref, else "main").
                         Errors with exit 2 if passed without --build-locally.
  -h, --help             Show this help.

Behavior:
  1. Validate <name> is in the catalogue and kind=oci-image (else exit 2).
  2. Resolve digest: --image-digest override > catalogue pins.stable digest.
  3. Docker CLI check + daemon check (exit 1 with actionable message on fail).
  4. If the image is already present at the resolved ref — no-op, exit 0.
  5. Else pull from the registry (or build if --build-locally), exit 0.
  6. On pull failure — exit 1 with fallback alternatives block.

Exit codes:
  0  image present (already or after pull/build)
  1  docker/pull/build failure
  2  bad usage (unknown MCP, wrong kind, --build-locally on pull-only MCP,
     --git-ref without --build-locally, bootstrap-placeholder digest)

Examples:
  eidolons mcp pull crystalium
  eidolons mcp pull atlas-aci --image-digest sha256:...
  eidolons mcp pull atlas-aci --build-locally --git-ref main
EOF
}

if [ $# -eq 0 ]; then
  usage
  exit 2
fi

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

mcp_name="${1:-}"
shift

# Collect remaining flags to forward to the driver.
extra_args=""
while [ $# -gt 0 ]; do
  case "$1" in
    --image-digest)
      [ -z "${2:-}" ] && { printf '%s\n' "--image-digest requires an argument" >&2; exit 2; }
      extra_args="${extra_args} --image-digest $2"
      shift 2
      ;;
    --build-locally)
      extra_args="${extra_args} --build-locally"
      shift
      ;;
    --git-ref)
      [ -z "${2:-}" ] && { printf '%s\n' "--git-ref requires an argument" >&2; exit 2; }
      extra_args="${extra_args} --git-ref $2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf '%s\n' "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate name is present.
if [ -z "$mcp_name" ]; then
  usage
  exit 2
fi

# Delegate to the generic pull driver (validates kind, digest, etc.).
# shellcheck disable=SC2086
mcp_driver_oci_image_pull "$mcp_name" $extra_args
