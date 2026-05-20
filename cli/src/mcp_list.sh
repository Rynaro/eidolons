#!/usr/bin/env bash
# cli/src/mcp_list.sh — list catalogue MCPs with install / health status.
#
# Usage: eidolons mcp list [--json]
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

JSON=false
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=true; shift ;;
    -h|--help)
      cat <<EOF
eidolons mcp list — list catalogue MCPs with install and health status

Usage: eidolons mcp list [--json]

Options:
  --json    Output as JSON array
  -h, --help  Show this help

Output columns (table mode):
  NAME       catalogue name
  SCOPE      system or eidolon:<name>
  INSTALLED  installed version or "—"
  LATEST     catalogue pins.stable
  UPDATE?    no | install | upgrade | downgrade
  HEALTH     ok | degraded | missing | (not installed)
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

cat_file="$(mcp_catalogue_file)"
if [ ! -f "$cat_file" ]; then
  warn "MCP catalogue not found at: $cat_file"
  exit 1
fi

lock_json="$(mcp_lock_read)"

if [ "$JSON" = "true" ]; then
  # Merge catalogue + lockfile data into a JSON array.
  mcp_catalogue_names="$(mcp_catalogue_list_names)"
  out_arr="[]"
  while IFS= read -r mname; do
    [ -z "$mname" ] && continue
    entry="$(mcp_catalogue_get "$mname")"
    installed_ver="$(printf '%s' "$lock_json" \
      | jq -r --arg n "$mname" '(.mcps // [])[] | select(.name == $n) | .version // ""')"
    latest="$(printf '%s' "$entry" | jq -r '.versions.pins.stable')"
    scope="$(printf '%s' "$entry" | jq -r '.scope')"
    kind="$(printf '%s' "$entry" | jq -r '.kind')"

    update="install"
    if [ -n "$installed_ver" ]; then
      if [ "$installed_ver" = "$latest" ]; then
        update="no"
      else
        update="upgrade"
      fi
    fi

    row="$(jq -n \
      --arg nm "$mname" \
      --arg sc "$scope" \
      --arg kd "$kind" \
      --arg iv "$installed_ver" \
      --arg lt "$latest" \
      --arg up "$update" \
      '{name:$nm, scope:$sc, kind:$kd, installed:$iv, latest:$lt, update:$up}')"
    out_arr="$(printf '%s' "$out_arr" | jq --argjson r "$row" '. + [$r]')"
  done <<< "$mcp_catalogue_names"
  printf '%s\n' "$out_arr"
  exit 0
fi

# Table output.
# Header.
printf '%-16s %-10s %-12s %-10s %-10s %s\n' \
  "NAME" "SCOPE" "INSTALLED" "LATEST" "UPDATE?" "HEALTH"
printf '%-16s %-10s %-12s %-10s %-10s %s\n' \
  "────────────────" "──────────" "────────────" "──────────" "──────────" "──────"

mcp_catalogue_names="$(mcp_catalogue_list_names)"
while IFS= read -r mname; do
  [ -z "$mname" ] && continue

  entry="$(mcp_catalogue_get "$mname")"
  latest="$(printf '%s' "$entry" | jq -r '.versions.pins.stable')"
  scope="$(printf '%s' "$entry" | jq -r '.scope')"

  installed_ver="$(printf '%s' "$lock_json" \
    | jq -r --arg n "$mname" '(.mcps // [])[] | select(.name == $n) | .version // ""')"

  if [ -n "$installed_ver" ]; then
    disp_installed="$installed_ver"
    if [ "$installed_ver" = "$latest" ]; then
      update="no"
    else
      update="upgrade"
    fi
    health="(not checked)"
  else
    disp_installed="—"
    update="install"
    health="missing"
  fi

  printf '%-16s %-10s %-12s %-10s %-10s %s\n' \
    "$mname" "$scope" "$disp_installed" "$latest" "$update" "$health"
done <<< "$mcp_catalogue_names"

echo ""
info "Run 'eidolons mcp show <name>' for full details."
info "Run 'eidolons mcp install <name>' to install."
info "Run 'eidolons mcp health <name>' for live health probes."
