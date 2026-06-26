#!/usr/bin/env bash
# cli/src/harness_hook.sh — hook-mode adapter for 'eidolons run --hook <host>'
# ═══════════════════════════════════════════════════════════════════════════
#
# Called by run.sh when --hook <host> is present. Wraps the routing artifact
# in the host-dialect hook JSON and writes it to stdout.
#
# Stdout contract:
#   - Non-trivial routing: valid JSON with hookSpecificOutput.hookEventName
#     and hookSpecificOutput.additionalContext (≤1000 tokens).
#   - Trivial / no-route / session-start absent: EMPTY stdout.
#   - Any error: EMPTY stdout, exit 0. (fail-open invariant)
#
# Called with env vars set by run.sh:
#   HOOK_HOST         — claude-code | codex
#   HOOK_MODE         — run | session_start
#   ARTIFACT_JSON     — routing artifact JSON (from run.sh kernel); empty for session_start
#   HOOK_EVENT_NAME   — UserPromptSubmit | SessionStart
#   PROMPT            — original prompt (for annotation in additionalContext)
#   HOOK_STDIN_INPUT  — raw stdin JSON (when --stdin was passed); may be empty
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# ── ESL forcing-function helpers (M1 + M2) ────────────────────────────────────
# Pure file reads (jq / grep / glob / awk) — NO docker, NO network. Each is
# fail-open: any error degrades to "absent"/"advisory"/empty so the caller's
# existing fail-open wrapper (`_main 2>/dev/null || true`) never breaks a
# session. Opt-in is enforced by _esl_tonberry_present (modeled on the
# crystalium tonberry-in-BOTH gate at cli/src/memory.sh:117-129).

# _esl_tonberry_present [ROOT] — 0 iff tonberry is in BOTH .mcp.json AND the lock.
_esl_tonberry_present() {
  local root="${1:-$(pwd)}"
  [ -f "$root/.mcp.json" ] || return 1
  jq -e '.mcpServers.tonberry' "$root/.mcp.json" >/dev/null 2>&1 || return 1
  [ -f "$root/eidolons.mcp.lock" ] || return 1
  grep -q "name: tonberry" "$root/eidolons.mcp.lock" 2>/dev/null || return 1
  return 0
}

# _esl_enforcement_mode [ROOT] — echo "block" or "advisory" (default advisory).
# Reads the `enforcement:` field from the tonberry lock entry via a small awk
# state machine (no yq dependency; the `enforcement_*` siblings do not match the
# anchored `^    enforcement:` line). Absent / unrecognized ⇒ advisory.
_esl_enforcement_mode() {
  local root="${1:-$(pwd)}"
  local lock="$root/eidolons.mcp.lock"
  local mode=""
  if [ -f "$lock" ]; then
    mode="$(awk '
      /^  - name: tonberry$/ { in_t=1; next }
      /^  - name: / { in_t=0 }
      in_t && /^    enforcement:/ {
        v=$2; gsub(/"/, "", v); print v; exit
      }
    ' "$lock" 2>/dev/null || true)"
  fi
  case "$mode" in
    block)    printf 'block' ;;
    *)        printf 'advisory' ;;
  esac
}

# _esl_inflight_change [ROOT] — echo "CHANGE_ID STATUS" for the first
# .spectra/changes/*/change.json whose status != archived; empty if none.
# Filters on status (not folder location) to be robust to both the MOVE and the
# tombstone archive layouts (spec OQ-4).
_esl_inflight_change() {
  local root="${1:-$(pwd)}"
  local f st cid
  for f in "$root"/.spectra/changes/*/change.json; do
    [ -f "$f" ] || continue
    st="$(jq -r '.status // ""' "$f" 2>/dev/null || echo "")"
    [ -n "$st" ] || continue
    [ "$st" = "archived" ] && continue
    cid="$(jq -r '.change_id // ""' "$f" 2>/dev/null || echo "")"
    [ -n "$cid" ] || continue
    printf '%s %s' "$cid" "$st"
    return 0
  done
  return 0
}

# _esl_render_block MODE RESUME — render the SessionStart ESL block (<=500 chars).
# MODE: "block" ⇒ "MUST"; anything else ⇒ "SHOULD". RESUME: "id status" or empty.
# Always names the trivial escape. The heading is the spec-fixed literal.
_esl_render_block() {
  local mode="$1"
  local resume="${2:-}"
  local imperative="SHOULD"
  [ "$mode" = "block" ] && imperative="MUST"
  printf '## ESL — spec lifecycle in effect\n'
  printf 'This project runs ESL (tonberry). You %s open a change before editing: mcp__tonberry__propose -> right_size. Trivial fixes -> Kupo / no-spec.' "$imperative"
  if [ -n "$resume" ]; then
    local rid rst
    rid="${resume%% *}"
    rst="${resume#* }"
    printf '\nRESUME: in-flight change %s (%s) — finish it before opening a new one.' "$rid" "$rst"
  fi
}

# ── Fail-open wrapper: any unhandled error → empty stdout, exit 0 ──────────
# We use a subshell pattern so errors inside _main don't reach the caller.
_main() {

  local hook_host="${HOOK_HOST:-}"
  local hook_mode="${HOOK_MODE:-run}"
  local event_name="${HOOK_EVENT_NAME:-UserPromptSubmit}"
  local artifact_json="${ARTIFACT_JSON:-}"
  local prompt_text="${PROMPT:-}"

  if [[ -z "$hook_host" ]]; then
    return 0  # misconfigured — fail-open
  fi

  # ── SessionStart mode: emit cortex digest ────────────────────────────────
  if [[ "$hook_mode" == "session_start" ]]; then
    local cortex_file=".eidolons/cortex/EIDOLONS.md"
    if [[ ! -f "$cortex_file" ]]; then
      return 0  # absent → empty stdout per AC-R1-3
    fi

    # Extract Roster Index and Dispatch Protocol sections via awk.
    # Target ≤1000 tokens (~4000 chars).
    local cortex_digest
    cortex_digest="$(awk '
      /^## Roster Index/ { in_section=1 }
      /^## Dispatch Protocol/ { in_section=1 }
      /^## / && !/^## Roster Index/ && !/^## Dispatch Protocol/ { in_section=0 }
      in_section { print }
    ' "$cortex_file" 2>/dev/null | head -c 4000 || true)"

    if [[ -z "$cortex_digest" ]]; then
      # Fallback: first 4000 chars of the file.
      cortex_digest="$(head -c 4000 "$cortex_file" 2>/dev/null || true)"
    fi

    if [[ -z "$cortex_digest" ]]; then
      return 0
    fi

    # ── Memory pre-flight (GAP-2): append crystalium recall digest ──────────
    # Runtime-gated: 'memory preflight' self-skips (empty stdout) when
    # crystalium is absent from .mcp.json / eidolons.mcp.lock, or docker is
    # unavailable, or on any error/timeout. NEVER blocks: failure = empty.
    local mem_digest=""
    local _mem_bin=""
    if _mem_bin="$(command -v eidolons 2>/dev/null)"; then
      mem_digest="$("$_mem_bin" memory preflight 2>/dev/null || true)"
    else
      _mem_bin="${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons"
      if [[ -x "$_mem_bin" ]]; then
        mem_digest="$("$_mem_bin" memory preflight 2>/dev/null || true)"
      fi
    fi
    if [[ -n "$mem_digest" ]]; then
      cortex_digest="${cortex_digest}

## Prior project memory (CRYSTALIUM recall)
${mem_digest}"
    fi

    # ── ESL forcing-function arm (M1): inject the "open a change" preflight ───
    # Opt-in: only when tonberry is in BOTH .mcp.json AND the lock. Reads only
    # (no .mcp.json write → G-NOCHURN; no docker). Appended into the SAME payload
    # AFTER the memory block; the jq emit below is unchanged. Fail-open: any
    # error in a helper degrades to no ESL block, so the cortex+memory still emit.
    if _esl_tonberry_present; then
      local esl_mode esl_resume esl_block
      esl_mode="$(_esl_enforcement_mode)"
      esl_resume="$(_esl_inflight_change)"
      esl_block="$(_esl_render_block "$esl_mode" "$esl_resume")"
      if [[ -n "$esl_block" ]]; then
        cortex_digest="${cortex_digest}

${esl_block}"
      fi
    fi

    # Emit JSON.
    jq -n \
      --arg en "SessionStart" \
      --arg ctx "$cortex_digest" \
      '{"hookSpecificOutput": {"hookEventName": $en, "additionalContext": $ctx}}'
    return 0
  fi

  # ── UserPromptSubmit mode: wrap routing artifact ──────────────────────────
  if [[ -z "$artifact_json" ]]; then
    return 0  # no artifact — fail-open
  fi

  local decision
  decision="$(printf '%s' "$artifact_json" | jq -r '.decision // "clarify"' 2>/dev/null || echo "clarify")"

  # Trivial/no-route: clarify decision with empty selected → empty stdout.
  if [[ "$decision" == "clarify" ]]; then
    return 0
  fi

  # Build additionalContext: compact routing summary ≤1000 tokens.
  local selected tier chain_str assumptions_str
  selected="$(printf '%s' "$artifact_json" | jq -r '(.selected // []) | join(", ")' 2>/dev/null || echo "")"
  tier="$(printf '%s' "$artifact_json" | jq -r '.tier // "standard"' 2>/dev/null || echo "standard")"
  chain_str="$(printf '%s' "$artifact_json" | jq -r '(.chain // []) | map(.eidolon) | join(" → ")' 2>/dev/null || echo "")"
  assumptions_str="$(printf '%s' "$artifact_json" | jq -r '(.assumptions // []) | join("; ")' 2>/dev/null || echo "")"

  # Construct the advisory context block (compact, ≤1000 tokens).
  local ctx_text
  if [[ -n "$chain_str" && "$chain_str" != "$selected" ]]; then
    ctx_text="Route: $selected  Tier: $tier  Chain: $chain_str  Instruction: Delegate to $selected via the Task tool now. Do NOT implement, edit, or debug directly in the main loop — dispatch to the named Eidolon subagent(s)."
  else
    ctx_text="Route: $selected  Tier: $tier  Chain: none  Instruction: Delegate to $selected via the Task tool now. Do NOT implement, edit, or debug directly in the main loop — dispatch to the named Eidolon subagent(s)."
  fi

  if [[ -n "$assumptions_str" ]]; then
    ctx_text="$ctx_text  Notes: $assumptions_str"
  fi

  # ── ESL rider (M2): append the "open a change first" clause on a real route ──
  # Only the non-trivial path reaches here (the clarify/trivial early-return at
  # the top already yields empty stdout = the inherited trivial escape, untouched
  # by M2). Opt-in: tonberry in BOTH .mcp.json AND lock. Strength tracks the
  # recorded enforcement mode. Fail-open: a helper error simply skips the clause.
  if _esl_tonberry_present; then
    local esl_mode_ups esl_clause
    esl_mode_ups="$(_esl_enforcement_mode)"
    if [[ "$esl_mode_ups" == "block" ]]; then
      esl_clause="ESL project: MUST open a change first — mcp__tonberry__propose -> right_size; trivial routes need no spec."
    else
      esl_clause="ESL project: open a change first (SHOULD) — mcp__tonberry__propose -> right_size; trivial routes need no spec."
    fi
    ctx_text="$ctx_text  $esl_clause"
  fi

  # Trim to ≤4000 chars to stay well under 1000 tokens.
  ctx_text="$(printf '%s' "$ctx_text" | cut -c1-4000)"

  jq -n \
    --arg en "UserPromptSubmit" \
    --arg ctx "$ctx_text" \
    '{"hookSpecificOutput": {"hookEventName": $en, "additionalContext": $ctx}}'
  return 0
}

# Run _main; on any error, emit nothing to stdout and exit 0 (fail-open).
_main 2>/dev/null || true
