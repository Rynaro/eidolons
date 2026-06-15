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
