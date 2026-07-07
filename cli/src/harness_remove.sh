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
# ECM P2 Track E (removal parity, AC-RM-1..6) additionally reverses ECM's own
# writes, fixing two P1 gaps plus the new P2 per-host surfaces:
#   - Strips 'compactThreshold' from .claude/settings.json (P1 gap, AC-RM-1)
#   - Strips 'context:' from eidolons.lock entirely (P1 gap, AC-RM-2)
#   - Strips the managed 'model_auto_compact_token_limit' line from
#     .codex/config.toml, when lock-recorded as managed=true (AC-RM-3)
#   - Strips the copilot ecm-context marker block from
#     .github/copilot-instructions.md, siblings preserved (AC-RM-4)
#   - Removes the cursor ECM static floor .cursor/rules/eidolons-context.mdc
#     (AC-RM-5)
# All ECM removal is managed-flag-aware (don't-clobber-aware): a foreign
# pre-existing value we never wrote is left untouched, mirroring install's
# own don't-clobber semantics.
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

# ── ECM P2 Track E: read managed flags BEFORE any lock mutation ───────────
# Don't-clobber-aware removal: only strip a value we (eidolons) actually
# wrote. Read once, up front, since the context: lock key itself gets
# stripped later in this same run (AC-RM-2) — after that point these flags
# would no longer be recoverable from the lock.
_ecm_compactthreshold_managed_lock="false"
_ecm_codex_autocompact_managed_lock="false"
if [[ -f "$PROJECT_LOCK" ]]; then
  _ecm_lock_json="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null || echo '{}')"
  _ecm_compactthreshold_managed_lock="$(printf '%s' "$_ecm_lock_json" | jq -r '.context.compactthreshold_managed // false' 2>/dev/null || echo false)"
  _ecm_codex_autocompact_managed_lock="$(printf '%s' "$_ecm_lock_json" | jq -r '.context.codex_autocompact_managed // false' 2>/dev/null || echo false)"
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

# ── ECM P2 Track E: strip compactThreshold from .claude/settings.json ────
# P1 gap fix (AC-RM-1). Don't-clobber-aware: only strip when THIS install
# actually wrote it (compactthreshold_managed=true in the lock, read above,
# before the lock's context: key itself gets stripped later in this run).
# A foreign pre-existing value (managed=false) is left untouched.
if [[ -f "$SETTINGS_JSON" ]] && [[ "$_ecm_compactthreshold_managed_lock" == "true" ]]; then
  if jq empty "$SETTINGS_JSON" 2>/dev/null && jq -e 'has("compactThreshold")' "$SETTINGS_JSON" >/dev/null 2>&1; then
    _ct_tmp="$(mktemp)"
    if jq 'del(.compactThreshold)' "$SETTINGS_JSON" > "$_ct_tmp" 2>/dev/null; then
      mv "$_ct_tmp" "$SETTINGS_JSON"
      ok "Removed compactThreshold from .claude/settings.json (ECM managed, AC-RM-1)"
    else
      rm -f "$_ct_tmp"
      warn "could not strip compactThreshold from $SETTINGS_JSON — leaving as-is (fail-open)"
    fi
  fi
fi

# ── Remove .codex/hooks.json ──────────────────────────────────────────────
CODEX_HOOKS=".codex/hooks.json"
if [[ -f "$CODEX_HOOKS" ]]; then
  rm -f "$CODEX_HOOKS"
  ok "Removed .codex/hooks.json"
fi

# ── ECM P2 Track E: strip model_auto_compact_token_limit from codex config ──
# (AC-RM-3). Don't-clobber-aware: only strip when lock-recorded managed=true.
CODEX_CONFIG_TOML=".codex/config.toml"
if [[ -f "$CODEX_CONFIG_TOML" ]] && [[ "$_ecm_codex_autocompact_managed_lock" == "true" ]]; then
  if grep -q '^model_auto_compact_token_limit' "$CODEX_CONFIG_TOML" 2>/dev/null; then
    _toml_tmp="$(mktemp)"
    # NOTE: 'grep -v' exits 1 (not an error) when EVERY line matches the
    # dropped pattern (i.e. the managed line was the file's only content) —
    # that is the common case here and must NOT be read as a write failure.
    # Capture the real exit code via '||' so 'set -e' does not abort on it;
    # only rc>=2 is an actual grep error.
    _toml_grep_rc=0
    grep -v '^model_auto_compact_token_limit' "$CODEX_CONFIG_TOML" > "$_toml_tmp" 2>/dev/null || _toml_grep_rc=$?
    if [[ "$_toml_grep_rc" -le 1 ]]; then
      mv "$_toml_tmp" "$CODEX_CONFIG_TOML"
      ok "Removed model_auto_compact_token_limit from .codex/config.toml (ECM managed, AC-RM-3)"
    else
      rm -f "$_toml_tmp"
      warn "could not strip model_auto_compact_token_limit from $CODEX_CONFIG_TOML — leaving as-is (fail-open)"
    fi
  fi
fi

# ── Remove .github/hooks/eidolons.json (copilot sessionStart adapter) ────
COPILOT_HOOKS_FILE=".github/hooks/eidolons.json"
if [[ -f "$COPILOT_HOOKS_FILE" ]]; then
  rm -f "$COPILOT_HOOKS_FILE"
  rmdir ".github/hooks" 2>/dev/null || true
  ok "Removed .github/hooks/eidolons.json"
fi

# ── ECM P2 Track E: strip the copilot ECM marker block (AC-RM-4) ─────────
# Marker-bounded (never hand-rolled awk); sibling content around the block
# is preserved byte-identically (upsert_marker_block/remove_marker_block
# contract, lib.sh:1290).
remove_marker_block ".github/copilot-instructions.md" "ecm-context"

# ── ECM P2 Track E: remove the cursor ECM static floor (AC-RM-5) ─────────
# Dedicated file (not the sync-owned eidolons-cortex.mdc) — a clean rm -f.
CURSOR_ECM_MDC=".cursor/rules/eidolons-context.mdc"
if [[ -f "$CURSOR_ECM_MDC" ]]; then
  rm -f "$CURSOR_ECM_MDC"
  rmdir ".cursor/rules" 2>/dev/null || true
  ok "Removed .cursor/rules/eidolons-context.mdc"
fi

# ── Remove opencode advisory plugin (strict R18/R-plugin) ────────────────
OPENCODE_PLUGIN=".opencode/plugins/eidolons.js"
if [[ -f "$OPENCODE_PLUGIN" ]]; then
  rm -f "$OPENCODE_PLUGIN"
  rmdir ".opencode/plugins" 2>/dev/null || true
  ok "Removed .opencode/plugins/eidolons.js"
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

# ── ECM P2 Track E: remove context: key from eidolons.lock (P1 gap, AC-RM-2) ──
# Same awk skip-block idiom as harness: above. Unconditional (unlike the
# managed-flag-aware removals above): the context: key itself is fully
# eidolons-owned the moment it exists (ECM's opt-in gate controls whether it
# gets WRITTEN, not whether removal is allowed to clean it up).
if [[ -f "$PROJECT_LOCK" ]] && grep -q '^context:' "$PROJECT_LOCK" 2>/dev/null; then
  _lock_no_context="$(awk '
    /^context:/ { skip=1; next }
    skip && /^[^[:space:]]/ { skip=0 }
    !skip { print }
  ' "$PROJECT_LOCK")"
  printf '%s\n' "$_lock_no_context" > "$PROJECT_LOCK"
  ok "Removed context: key from eidolons.lock (ECM, AC-RM-2)"
fi

ok "Harness removed."
