#!/usr/bin/env bash
# cli/src/harness_status.sh — eidolons harness status
# ═══════════════════════════════════════════════════════════════════════════
#
# Reports:
#   - Wired hosts (from eidolons.lock harness: key)
#   - Effective tier per host (T3 inject tier = all hosts in P1)
#   - Shim paths
#   - Schema version
#   - Warns about .codex/agents/<name>.md files (G10: Codex only reads .toml)
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<EOF
eidolons harness status — report hook wiring state

Usage: eidolons harness status [OPTIONS]

Options:
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown option: $1 (see 'eidolons harness status --help')" ;;
  esac
done

# ── Read lockfile ──────────────────────────────────────────────────────────
if [[ ! -f "$PROJECT_LOCK" ]]; then
  info "No eidolons.lock found. Run 'eidolons sync' first."
  printf 'harness: not installed\n'
  exit 0
fi

_lock_json="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null || echo '{}')"
_schema_ver="$(printf '%s' "$_lock_json" | jq -r '.harness.schema_version // "absent"' 2>/dev/null || echo "absent")"

if [[ "$_schema_ver" == "absent" ]]; then
  printf 'harness: not installed\n'
  printf 'Run: eidolons harness install\n'
  exit 0
fi

_hosts_json="$(printf '%s' "$_lock_json" | jq -r '(.harness.hosts_wired // [])[]' 2>/dev/null || echo "")"
_shims_json="$(printf '%s' "$_lock_json" | jq -r '(.harness.shim_paths // [])[]' 2>/dev/null || echo "")"
_settings_patched="$(printf '%s' "$_lock_json" | jq -r '.harness.settings_json_patched // false' 2>/dev/null || echo "false")"
_codex_patched="$(printf '%s' "$_lock_json" | jq -r '.harness.codex_hooks_json_patched // false' 2>/dev/null || echo "false")"

printf 'harness status\n'
printf '  schema_version:    %s\n' "$_schema_ver"
printf '  wired hosts:\n'

# Tier table: all hosts are T3 (inject tier) in P1.
# T3 = read-only context injection via additionalContext; no blocking hooks.
while IFS= read -r _host; do
  [[ -z "$_host" ]] && continue
  printf '    - %s  (tier: T3 — inject)\n' "$_host"
done <<EOF
$_hosts_json
EOF

printf '  settings.json patched: %s\n' "$_settings_patched"
printf '  codex hooks.json patched: %s\n' "$_codex_patched"

printf '  shim paths:\n'
while IFS= read -r _shim; do
  [[ -z "$_shim" ]] && continue
  if [[ -f "$_shim" ]]; then
    printf '    - %s  [present]\n' "$_shim"
  else
    printf '    - %s  [MISSING]\n' "$_shim"
    warn "Shim missing: $_shim. Run 'eidolons harness install --force' to restore."
  fi
done <<EOF
$_shims_json
EOF

# ── G10 warning: .codex/agents/<name>.md exists but only .toml is read ────
_members_csv="$(printf '%s' "$_lock_json" | jq -r '(.members // []) | map(.name) | join(",")' 2>/dev/null || echo "")"
if printf '%s' ",$_hosts_json," | tr '\n' ',' | grep -q ",codex,"; then
  for _mname in $(printf '%s' "$_members_csv" | tr ',' ' '); do
    [[ -z "$_mname" ]] && continue
    if [[ -f ".codex/agents/$_mname.md" ]] && [[ -f ".codex/agents/$_mname.toml" ]]; then
      warn ".codex/agents/$_mname.md exists but Codex only reads .toml; consider removal"
    fi
  done
fi

ok "Harness is installed."
