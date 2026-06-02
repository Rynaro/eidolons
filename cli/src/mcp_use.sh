#!/usr/bin/env bash
# cli/src/mcp_use.sh — switch an installed MCP to any catalogue-published version.
#
# Usage: eidolons mcp use <name>@<ver> [--no-pull] [--project-root PATH]
#
# Downgrades allowed (use explicitly requests a specific version).
# Forward-only enforcement lives in mcp_upgrade.sh; this command is unrestricted.
# A version is switchable ONLY if it exists in the catalogue under
# versions.releases.<ver> — unpublished versions are rejected.
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
eidolons mcp use — switch an installed MCP to a specific catalogue-published version

Usage: eidolons mcp use <name>@<ver> [--no-pull] [--project-root PATH]

Arguments:
  name@ver        MCP name and target version (the @<ver> suffix is mandatory).
                  The version must be published in the roster catalogue.

Options:
  --no-pull            Suppress auto-pull for oci-image MCPs.
                       If the image is missing, the switch aborts.
                       Accepted and ignored for kind=binary (no-op).
  --project-root PATH  Project directory to install into (default: cwd).
  -h, --help           Show this help.

Examples:
  eidolons mcp use junction@0.1.0
  eidolons mcp use crystalium@1.2.0
  eidolons mcp use atlas-aci@0.2.2 --no-pull
EOF
}

# Refresh the nexus roster data so catalogue version records are current.
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

no_pull=false
project_root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-pull)       no_pull=true; shift ;;
    --project-root)
      [ -z "${2:-}" ] && die "--project-root requires an argument"
      project_root="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    -*) warn "Unknown option: $1"; usage >&2; exit 2 ;;
    *) warn "Unexpected argument: $1"; usage >&2; exit 2 ;;
  esac
done

# Mandatory @<ver> suffix — reject bare names.
case "$name_ver" in
  *@*)
    name="${name_ver%%@*}"
    ver="${name_ver#*@}"
    ;;
  *)
    echo "error: 'eidolons mcp use' requires a version: use <name>@<ver>" >&2
    usage >&2
    exit 2
    ;;
esac

if [ -z "$name" ] || [ -z "$ver" ]; then
  echo "error: 'eidolons mcp use' requires a version: use <name>@<ver>" >&2
  usage >&2
  exit 2
fi

# Validate catalogue entry exists.
mcp_resolve_kind "$name" > /dev/null

# Assert the requested version is published in the catalogue.
mcp_assert_version_published "$name" "$ver"

# No-op idempotency: if already at the requested version, skip re-install.
current="$(mcp_lock_entry "$name" | jq -r '.version // ""')"
if [ "$current" = "$ver" ]; then
  info "${name} already at ${ver} — no-op"
  exit 0
fi

# Require the MCP to be installed (lock entry must exist).
if [ -z "$current" ]; then
  die "${name} is not installed. Run 'eidolons mcp install ${name}@${ver}' first."
fi

say "Switching ${name}: ${current} → ${ver}"

if [ "$no_pull" = "true" ]; then
  if [ -n "$project_root" ]; then
    bash "$SELF_DIR/mcp_install.sh" "${name}@${ver}" --force --no-pull --project-root "$project_root"
  else
    bash "$SELF_DIR/mcp_install.sh" "${name}@${ver}" --force --no-pull
  fi
else
  if [ -n "$project_root" ]; then
    bash "$SELF_DIR/mcp_install.sh" "${name}@${ver}" --force --project-root "$project_root"
  else
    bash "$SELF_DIR/mcp_install.sh" "${name}@${ver}" --force
  fi
fi

ok "${name} switched to ${ver}."
