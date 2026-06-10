#!/usr/bin/env bash
# cli/src/harness_status.sh — eidolons harness status
# ═══════════════════════════════════════════════════════════════════════════
#
# Reports:
#   - Wired hosts (from eidolons.lock harness: key)
#   - Effective tier per host (FORGE ladder: T3/T2/T1)
#   - Cursor static-surface presence (.cursor/rules/eidolons-cortex.mdc, AGENTS.md pointer)
#   - Shim paths
#   - Schema version
#   - Warns about .codex/agents/<name>.md files (G10: Codex only reads .toml)
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.
# Read-only: no host binary probes (existence/grep checks only). Exit 0 always.

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

# _harness_effective_tier HOST → "T3", "T2", or "T1" to stdout + rationale to stderr
# Read-only case-based lookup; no host binary executed (AC-R13-3).
_harness_effective_tier() {
  case "$1" in
    claude-code) printf 'T3' ;;
    codex)       printf 'T3' ;;
    copilot)     printf 'T2' ;;
    cursor)      printf 'T2' ;;
    opencode)    printf 'T1' ;;
    *)           printf 'T?' ;;
  esac
}

_harness_tier_rationale() {
  case "$1" in
    claude-code) printf 'full route-inject (UserPromptSubmit + SessionStart)' ;;
    codex)       printf 'route-inject; [A1] hooks.json schema unverified' ;;
    copilot)     printf 'static-inject + best-effort sessionStart ([#2142] context may be dropped)' ;;
    cursor)      printf 'static-only (.mdc + AGENTS.md); hooks runtime-broken through v2.4.7' ;;
    opencode)    printf 'gate-only floor; not yet wired (P3)' ;;
    *)           printf 'unknown host' ;;
  esac
}

printf 'harness status\n'
printf '  schema_version:    %s\n' "$_schema_ver"
printf '  wired hosts:\n'

while IFS= read -r _host; do
  [[ -z "$_host" ]] && continue
  _tier="$(_harness_effective_tier "$_host")"
  _rationale="$(_harness_tier_rationale "$_host")"
  printf '    - %s  (tier: %s — %s)\n' "$_host" "$_tier" "$_rationale"
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

# ── Cursor static-surface presence report (R13 AC-R13-2) ─────────────────
# Driven by manifest hosts.wire (cursor is not a harness-installable host —
# its surfaces ride sync). Read-only existence/grep checks only; no host binary.
_manifest_hosts=""
if [[ -f "$PROJECT_MANIFEST" ]]; then
  _manifest_hosts="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
    | jq -r '(.hosts.wire // []) | join(",")' 2>/dev/null || echo "")"
fi
if printf '%s' ",$_manifest_hosts," | grep -q ",cursor,"; then
  printf '  cursor static surfaces:\n'
  if [[ -f ".cursor/rules/eidolons-cortex.mdc" ]]; then
    printf '    .cursor/rules/eidolons-cortex.mdc  [present]\n'
  else
    printf '    .cursor/rules/eidolons-cortex.mdc  [absent] — run eidolons sync to create\n'
  fi
  if grep -qF "<!-- eidolon:dispatch-pointer start -->" AGENTS.md 2>/dev/null; then
    printf '    AGENTS.md dispatch-pointer block    [present]\n'
  else
    printf '    AGENTS.md dispatch-pointer block    [absent] — run eidolons sync to create\n'
  fi
fi

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
