#!/usr/bin/env bash
# cli/src/mcp_upgrade.sh — upgrade installed MCPs to catalogue pins.stable.
#
# Usage: eidolons mcp upgrade [<name>[@<ver>]|--all] [--no-pull]
#
# With no arguments or --all: upgrades all installed MCPs to catalogue pins.stable.
# With <name>: upgrades a specific MCP to catalogue pins.stable.
# With <name>@<ver>: upgrades to an explicit published version (forward-only;
#   downgrades are rejected — use 'eidolons mcp use <name>@<ver>' instead).
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

Usage: eidolons mcp upgrade [<name>[@<ver>]|--all] [--no-pull]

Arguments:
  name          Upgrade a specific MCP to catalogue pins.stable.
  name@ver      Upgrade a specific MCP to an explicit published version
                (forward-only; use 'eidolons mcp use name@ver' to downgrade).
  --all         Upgrade all installed MCPs to catalogue pins.stable.
                If neither is given, defaults to --all.
                Cannot be combined with a name@ver explicit version.

Options:
  --no-pull   Suppress auto-pull for oci-image MCPs during upgrade.
              If the image is missing, the upgrade aborts for that MCP.
              Accepted and ignored for kind=binary (no-op).
  -h, --help  Show this help
EOF
}

# Refresh the nexus roster data before reading the catalogue so that
# pins.stable bumps on the channel ref are picked up automatically (STORY-7).
# Inherits all skip-guards (EIDOLONS_NEXUS / EIDOLONS_SKIP_REFRESH) and is
# non-fatal on network failure.
nexus_refresh

target=""
explicit_ver=""
no_pull=false
all_flag=false
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     all_flag=true; shift ;;
    --no-pull) no_pull=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        warn "Unknown option: $1"; usage >&2; exit 2 ;;
    *)
      # Detect name@ver form.
      case "$1" in
        *@*)
          target="${1%%@*}"
          explicit_ver="${1#*@}"
          ;;
        *)
          target="$1"
          ;;
      esac
      shift
      ;;
  esac
done

# --all + explicit @ver is a usage error (regardless of argument order).
if [ "$all_flag" = "true" ] && [ -n "$explicit_ver" ]; then
  echo "error: --all cannot be combined with an explicit version (@${explicit_ver})" >&2
  usage >&2
  exit 2
fi

# Resolve target: --all flag takes precedence over a bare target.
if [ "$all_flag" = "true" ]; then
  target="--all"
fi

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

# Explicit-version branch: upgrade <name>@<ver> (forward-only).
if [ -n "$explicit_ver" ]; then
  # Validate catalogue entry exists.
  mcp_resolve_kind "$target" > /dev/null

  # Assert the requested version is published in the catalogue.
  mcp_assert_version_published "$target" "$explicit_ver"

  # Read installed version.
  current="$(mcp_lock_entry "$target" | jq -r '.version // ""')"

  # No-op idempotency: already at target.
  if [ -n "$current" ] && [ "$current" = "$explicit_ver" ]; then
    info "${target} already at ${explicit_ver} — no-op"
    ok "Upgrade complete."
    exit 0
  fi

  # Direction gate: reject downgrades.
  if [ -n "$current" ] && semver_lt "$explicit_ver" "$current"; then
    die "${explicit_ver} is older than the installed version (${current}). Use 'eidolons mcp use ${target}@${explicit_ver}' to downgrade."
  fi

  say "Upgrading ${target}: ${current:-<not installed>} → ${explicit_ver}"
  if [ "$no_pull" = "true" ]; then
    bash "$SELF_DIR/mcp_install.sh" "${target}@${explicit_ver}" --force --no-pull
  else
    bash "$SELF_DIR/mcp_install.sh" "${target}@${explicit_ver}" --force
  fi
  ok "Upgrade complete."
  exit 0
fi

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
