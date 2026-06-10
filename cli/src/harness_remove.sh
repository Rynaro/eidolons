#!/usr/bin/env bash
# cli/src/harness_remove.sh — eidolons harness remove
# ═══════════════════════════════════════════════════════════════════════════
#
# Reverses `eidolons harness install`:
#   - Removes .eidolons/harness/hooks/ shim files
#   - Removes the "hooks" key from .claude/settings.json (jq-delete)
#   - Removes .codex/hooks.json (if present and eidolons-written)
#   - Removes the harness: key from eidolons.lock
#
# Keys NOT added by eidolons harness remain intact in settings.json.
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

HARNESS_SHIM_DIR=".eidolons/harness/hooks"

usage() {
  cat <<EOF
eidolons harness remove — remove hook shims and settings wiring

Usage: eidolons harness remove [OPTIONS]

Options:
  -h, --help    Show this help

Removes:
  - .eidolons/harness/hooks/*.sh  (shim scripts)
  - hooks key from .claude/settings.json
  - .codex/hooks.json (if present)
  - harness: key from eidolons.lock
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown option: $1 (see 'eidolons harness remove --help')" ;;
  esac
done

manifest_exists || die "No eidolons.yaml found. Run 'eidolons init' first."

# ── Check harness is installed ─────────────────────────────────────────────
_lock_schema="absent"
if [[ -f "$PROJECT_LOCK" ]]; then
  _lock_schema="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r '.harness.schema_version // "absent"' 2>/dev/null || echo "absent")"
fi

if [[ "$_lock_schema" == "absent" ]]; then
  info "Harness is not installed (no harness: key in eidolons.lock). Nothing to remove."
  exit 0
fi

# ── Remove shim files ──────────────────────────────────────────────────────
if [[ -d "$HARNESS_SHIM_DIR" ]]; then
  # Remove only the shim scripts we manage (matching naming pattern).
  _removed_shims=false
  for _shim in "$HARNESS_SHIM_DIR"/*.sh; do
    [[ -f "$_shim" ]] || continue
    rm -f "$_shim"
    info "  removed shim: $_shim"
    _removed_shims=true
  done
  # Remove directory if now empty.
  rmdir "$HARNESS_SHIM_DIR" 2>/dev/null || true
  if [[ "$_removed_shims" == "true" ]]; then
    ok "Removed harness shim scripts"
  fi
fi

# ── Remove hooks from .claude/settings.json ───────────────────────────────
SETTINGS_JSON=".claude/settings.json"
if [[ -f "$SETTINGS_JSON" ]]; then
  if jq empty "$SETTINGS_JSON" 2>/dev/null; then
    # Check if hooks key exists before removing.
    _has_hooks="$(jq -r 'if has("hooks") then "yes" else "no" end' "$SETTINGS_JSON" 2>/dev/null || echo "no")"
    if [[ "$_has_hooks" == "yes" ]]; then
      _tmp="$(mktemp)"
      if jq 'del(.hooks)' "$SETTINGS_JSON" > "$_tmp" 2>/dev/null; then
        mv "$_tmp" "$SETTINGS_JSON"
        ok "Removed hooks key from .claude/settings.json (other keys preserved)"
      else
        rm -f "$_tmp"
        warn "jq del(.hooks) failed — .claude/settings.json not modified"
      fi
    else
      info ".claude/settings.json has no hooks key (already removed or never wired)"
    fi
  else
    warn ".claude/settings.json is not valid JSON — skipping hooks removal"
  fi
fi

# ── Remove .codex/hooks.json ──────────────────────────────────────────────
CODEX_HOOKS=".codex/hooks.json"
if [[ -f "$CODEX_HOOKS" ]]; then
  rm -f "$CODEX_HOOKS"
  ok "Removed .codex/hooks.json"
fi

# ── Remove harness: key from eidolons.lock ────────────────────────────────
if [[ -f "$PROJECT_LOCK" ]]; then
  _lock_no_harness="$(python3 - "$PROJECT_LOCK" <<'PY'
import sys, re
content = open(sys.argv[1]).read()
content = re.sub(r'^harness:.*?(?=^\w|\Z)', '', content, flags=re.MULTILINE|re.DOTALL)
sys.stdout.write(content.rstrip('\n') + '\n')
PY
)"
  printf '%s\n' "$_lock_no_harness" > "$PROJECT_LOCK"
  ok "Removed harness: key from eidolons.lock"
fi

ok "Harness removed."
