#!/usr/bin/env bash
# cli/src/harness_remove.sh — eidolons harness remove
# ═══════════════════════════════════════════════════════════════════════════
#
# Reverses `eidolons harness install`:
#   - Removes .eidolons/harness/hooks/ shim files
#   - Removes only our hook entries from .claude/settings.json (jq-filter)
#   - Removes .codex/hooks.json (if present and eidolons-written)
#   - Removes the harness: key from eidolons.lock
#
# Spec R2 (FINDING-1): only eidolons-written entries are removed from hooks
# arrays; entries added by other tools are preserved byte-identically.
# Event keys are deleted only when their array becomes empty.
# The hooks key is deleted only when it becomes an empty object.
#
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
  - Our hook entries from .claude/settings.json (other entries preserved)
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

# ── Remove our hook entries from .claude/settings.json ────────────────────
# Spec R2 (FINDING-1): filter each event array to drop only entries whose
# hooks[].command matches our shim paths. Delete an event key only when its
# array becomes empty. Delete the hooks key only when it becomes {}.
# All other keys and entries are preserved byte-identically.
SETTINGS_JSON=".claude/settings.json"
if [[ -f "$SETTINGS_JSON" ]]; then
  if jq empty "$SETTINGS_JSON" 2>/dev/null; then
    _has_hooks="$(jq -r 'if has("hooks") then "yes" else "no" end' "$SETTINGS_JSON" 2>/dev/null || echo "no")"
    if [[ "$_has_hooks" == "yes" ]]; then
      _existing_canonical="$(jq -cS . "$SETTINGS_JSON" 2>/dev/null || echo "")"
      # Our shim commands match the pattern ".eidolons/harness/hooks/claude-code-*.sh".
      # jq: for each event array, filter out entries whose nested command matches our path prefix.
      # An entry is "ours" if any of its hooks[].command starts with HARNESS_SHIM_DIR.
      _shim_prefix="$HARNESS_SHIM_DIR/"
      _tmp="$(mktemp)"
      jq \
        --arg prefix "$_shim_prefix" \
        '
        # Helper: true if an entry has any hooks[].command starting with $prefix
        def is_ours(entry):
          (entry.hooks? // [] | map(.command? // "") | any(startswith($prefix)));

        # Filter each event array; delete event key if array becomes empty.
        if has("hooks") then
          .hooks = (
            .hooks | to_entries | map(
              .value = (.value | map(select(is_ours(.) | not))) |
              select(.value | length > 0)
            ) | from_entries
          ) |
          # Delete hooks key entirely if it becomes an empty object.
          if (.hooks | length) == 0 then del(.hooks) else . end
        else .
        end
        ' "$SETTINGS_JSON" > "$_tmp" 2>/dev/null && mv "$_tmp" "$SETTINGS_JSON" || rm -f "$_tmp"
      _after_canonical="$(jq -cS . "$SETTINGS_JSON" 2>/dev/null || echo "")"
      if [[ "$_existing_canonical" != "$_after_canonical" ]]; then
        ok "Removed eidolons hook entries from .claude/settings.json (other keys preserved)"
      else
        info ".claude/settings.json had no eidolons hook entries to remove"
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

# ── Remove .github/hooks/eidolons.json (copilot sessionStart adapter) ────
COPILOT_HOOKS_FILE=".github/hooks/eidolons.json"
if [[ -f "$COPILOT_HOOKS_FILE" ]]; then
  rm -f "$COPILOT_HOOKS_FILE"
  rmdir ".github/hooks" 2>/dev/null || true
  ok "Removed .github/hooks/eidolons.json"
fi

# ── Remove harness: key from eidolons.lock (awk — FINDING-3 fix) ─────────
if [[ -f "$PROJECT_LOCK" ]]; then
  # awk: suppress lines from /^harness:/ until next top-level key or EOF.
  _lock_no_harness="$(awk '
    /^harness:/ { skip=1; next }
    skip && /^[^[:space:]]/ { skip=0 }
    !skip { print }
  ' "$PROJECT_LOCK")"
  printf '%s\n' "$_lock_no_harness" > "$PROJECT_LOCK"
  ok "Removed harness: key from eidolons.lock"
fi

ok "Harness removed."
