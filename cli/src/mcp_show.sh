#!/usr/bin/env bash
# cli/src/mcp_show.sh — show details for a specific MCP.
#
# Usage: eidolons mcp show <name>
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

if [ $# -eq 0 ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<EOF
eidolons mcp show — show details for a specific MCP

Usage: eidolons mcp show <name>

Arguments:
  name    MCP name (see: eidolons mcp list)

Options:
  -h, --help  Show this help
EOF
  exit 0
fi

name="$1"

entry="$(mcp_catalogue_get "$name")"
if [ -z "$entry" ]; then
  printf "MCP '%s' not found in catalogue. Try: eidolons mcp list\n" "$name" >&2
  exit 1
fi

lock_entry="$(mcp_lock_entry "$name")"

# Extract fields.
display_name="$(printf '%s' "$entry" | jq -r '.display_name')"
scope="$(printf '%s' "$entry" | jq -r '.scope')"
kind="$(printf '%s' "$entry" | jq -r '.kind')"
description="$(printf '%s' "$entry" | jq -r '.description')"
latest="$(printf '%s' "$entry" | jq -r '.versions.latest')"
stable="$(printf '%s' "$entry" | jq -r '.versions.pins.stable')"

installed_ver=""
installed_at=""
if [ -n "$lock_entry" ]; then
  installed_ver="$(printf '%s' "$lock_entry" | jq -r '.version // ""')"
  installed_at="$(printf '%s' "$lock_entry" | jq -r '.installed_at // ""')"
fi

# Source info.
source_type="$(printf '%s' "$entry" | jq -r '.source.type')"
source_url=""
case "$source_type" in
  ghcr)
    source_url="$(printf '%s' "$entry" | jq -r '.source.image')"
    ;;
  github_release)
    repo="$(printf '%s' "$entry" | jq -r '.source.repo')"
    source_url="https://github.com/${repo}"
    ;;
  url)
    source_url="$(printf '%s' "$entry" | jq -r '.source.url')"
    ;;
esac

# Print.
printf 'Name:           %s (%s)\n' "$name" "$display_name"
printf 'Scope:          %s\n' "$scope"
printf 'Kind:           %s\n' "$kind"
printf 'Description:    %s\n' "$description"
printf '\nUse cases:\n'
printf '%s' "$entry" | jq -r '.use_cases[]' | while IFS= read -r uc; do
  printf '  - %s\n' "$uc"
done

rel_eidolons="$(printf '%s' "$entry" | jq -r '(.related_eidolons // []) | join(", ")')"
if [ -n "$rel_eidolons" ]; then
  printf '\nRelated Eidolons: %s\n' "$rel_eidolons"
fi

printf '\nSource:         %s (%s)\n' "$source_url" "$source_type"

printf '\nVersions:\n'
printf '  latest:       %s\n' "$latest"
printf '  pins.stable:  %s\n' "$stable"

printf '\nInstalled:      '
if [ -n "$installed_ver" ]; then
  printf '%s\n' "$installed_ver"
  if [ -n "$installed_at" ]; then
    printf 'Installed at:   %s\n' "$installed_at"
  fi
else
  printf 'not installed\n'
fi

# hosts_wired.
hosts_wired="$(printf '%s' "$entry" | jq -r '(.install.hosts_wired // []) | join(", ")')"
if [ -n "$hosts_wired" ]; then
  printf '\nHosts wired:    %s\n' "$hosts_wired"
fi

# health probes.
probes="$(printf '%s' "$entry" | jq -r '(.health.probes // []) | join(", ")')"
printf '\nHealth probes:  %s\n' "$probes"

if [ -n "$installed_ver" ]; then
  printf '\nHealth status:\n'
  bash "$SELF_DIR/mcp_health.sh" "$name" 2>/dev/null | while IFS= read -r hline; do
    printf '  %s\n' "$hline"
  done
fi
