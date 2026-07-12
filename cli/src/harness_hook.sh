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
# shellcheck disable=SC1091
. "$SELF_DIR/lib_context.sh"

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

# ── ECM P1 (context-lifecycle kernel) helpers (T-F) ───────────────────────
# Pure reads + a bounded 'eidolons memory preflight' reuse. Fail-open: any
# absence/error degrades to an empty string, never breaks the caller.

# _ecm_project_enabled [ROOT] — 0 iff the CONSUMER PROJECT's eidolons.yaml
# declares a 'context:' block with enabled != false (P0-1 opt-in gate,
# mirrors _esl_tonberry_present's shape). Absent eidolons.yaml/context block
# -> disabled (AC-15) — this is what keeps ECM's SessionStart/UserPromptSubmit
# additions byte-silent for every project that has not opted in, even though
# the nexus-shipped roster/pins.yaml / roster/context-policy.yaml always
# exist on disk (those are nexus config, not a per-project opt-in signal).
_ecm_project_enabled() {
  local root="${1:-$(pwd)}"
  [ -f "$root/eidolons.yaml" ] || return 1
  local en
  en="$(yaml_to_json "$root/eidolons.yaml" 2>/dev/null \
    | jq -r 'if (.context // null) == null then "false"
             elif (.context.enabled // true) then "true"
             else "false" end' 2>/dev/null || echo false)"
  [ "$en" = "true" ]
}

# _ecm_pins_reminder — echo a compact comma-joined pin-id reminder from
# roster/pins.yaml (the nexus default pin set, spec §3.2). Empty on any
# read failure.
_ecm_pins_reminder() {
  local pins_file
  pins_file="$(context_pins_file 2>/dev/null || true)"
  [ -n "$pins_file" ] && [ -f "$pins_file" ] || return 0
  yaml_to_json "$pins_file" 2>/dev/null \
    | jq -r '(.pins // []) | map(.id) | join(", ")' 2>/dev/null || true
}

# _ecm_handoff_digest — lifted to lib.sh (shared with harness_install.sh's
# copilot install-time snapshot, ecm-p2-host-adapters drift fix). Both files
# source lib.sh at the top; the function is used here unchanged.

# ── atlas-aci auto-sync (harness step) ─────────────────────────────────────
# Pure reads + one bounded `docker run -d` spawn. Fires on BOTH SessionStart
# and UserPromptSubmit (spec §"Behaviour") so the code-graph converges on the
# working tree within ~one turn of any edit. On by default; opt-out only.
# Never touches stdout (the caller redirects this call to /dev/null) and
# never raises — every gate failure is a silent `return 0`, on top of the
# outer `_main 2>/dev/null || true` fail-open wrapper.

# _atlas_autosync [ROOT] — silent no-op unless ALL hold:
#   1. atlas-aci is wired: .mcpServers["atlas-aci"] in ROOT/.mcp.json (AC-1).
#   2. Not disabled: ROOT/eidolons.yaml .harness.atlas_sync.enabled != false.
#      Absent block/key/file => enabled (opt-out, the inverse of ECM's
#      opt-in _ecm_project_enabled above) (AC-2).
#   3. docker is on PATH (AC-5).
# When all hold, reuses the EXACT pinned image digest AND the EXACT
# eidolons.project slug from atlas-aci's OWN `serve` args in .mcp.json —
# never resolves/recomputes either independently (AC-3). A different digest
# can produce a different SCHEMA_EPOCH DB that `serve` then rejects with
# INDEX_UNAVAILABLE; a different slug would diverge the sync container's
# eidolons.project label from the serve container's, breaking
# `docker ps --filter label=...` grouping. Absent label (older wiring) is a
# fail-open no-op rather than guessing a slug from a different helper
# (memory_probe_project_slug / project_slug are for OTHER surfaces and can
# disagree with the mcp-install slug baked into .mcp.json).
# Dedups by container name atlas-aci-sync-<slug>: skips the spawn if one
# already exists (AC-4). Spawns `docker run --rm -d --pull=never` (detached,
# returns immediately — AC-5) with /repo mounted READ-WRITE (the inverse of
# serve's `:ro` — index writes .atlas/graph.<epoch>.db).
# --pull=never is load-bearing for AC-5, not cosmetic: `-d` only defers the
# CONTAINER's lifetime, not image ACQUISITION — a plain `docker run -d` on a
# not-yet-local image pulls synchronously in the foreground before ever
# detaching, blocking the prompt path on a multi-hundred-MB pull. With
# --pull=never, an absent-locally image makes `docker run` fail FAST instead
# (`|| true` -> silent no-op) rather than pulling. In normal operation the
# image IS already local, because `serve` runs from the same digest the user
# is already using — so --pull=never never removes real functionality, it
# only removes the possibility of a foreground pull blocking a turn.
# Both docker calls (the `ps` dedup probe and the `run` spawn) are wrapped in
# `with_timeout` (lib.sh:616, already in scope — this file sources lib.sh at
# the top) rather than a hand-rolled timeout(1)-or-background-watcher idiom:
# with_timeout is the ONE bash-3.2-safe timeout idiom this repo already uses
# repo-wide (lib_context.sh's per-turn meter refresh, memory.sh's preflight,
# canary, doctor, release) and its FD-hygiene fix (lib.sh:607-615) is exactly
# what keeps a `$(with_timeout ...)` capture from blocking on an orphaned
# timer. `docker ps` failing fast on a DOWN daemon (~10-15ms, verified
# empirically) does not cover a daemon that is UP but wedged (Docker Desktop
# stalled, storage stall, overloaded host) — an unbounded synchronous call
# there can hang the turn indefinitely, which is exactly what a fixed
# wall-clock bound closes. Bound: 1.5s, matching lib_context.sh's
# ECM_MEMORY_TIMEOUT_S — this call fires on EVERY UserPromptSubmit (the same
# hot-path class as ECM's PostToolUse meter refresh), not a once-per-session
# SessionStart-only budget like memory.sh's 8s. On timeout, with_timeout
# returns 124 -> `|| true` -> fail-open (an empty dedup probe result falls
# through to a spawn attempt; a killed spawn just means no container this
# turn — both are backstopped by --name uniqueness / the single-writer lock,
# never a wedged turn).
# cwd bound (documented, not fixed here): the mount root is the hook's cwd,
# which every wired host (claude-code/codex/copilot) sets to the project
# root before invoking the shim — see the SPEC/README note on the one known
# nested-workspace edge (a different, also-atlas-aci-wired project root as
# cwd would reindex THAT tree instead; not solved by this change).
_atlas_autosync() {
  local root="${1:-$(pwd)}"
  local mcp="$root/.mcp.json"

  # Gate 1 (AC-1): atlas-aci must be wired.
  [ -f "$mcp" ] || return 0
  jq -e '.mcpServers["atlas-aci"]' "$mcp" >/dev/null 2>&1 || return 0

  # Gate 2 (AC-2): opt-out. Absent block/key/file => enabled. Mirrors the
  # has("enabled") idiom (not `// true`, which would also fire on an
  # explicit `false` — jq's `//` treats `false` as substitutable).
  if [ -f "$root/eidolons.yaml" ]; then
    local _atlas_sync_enabled
    _atlas_sync_enabled="$(yaml_to_json "$root/eidolons.yaml" 2>/dev/null \
      | jq -r '(.harness.atlas_sync // {}) | if has("enabled") then (.enabled | tostring) else "true" end' 2>/dev/null || echo true)"
    [ "$_atlas_sync_enabled" = "false" ] && return 0
  fi

  # Gate 3 (AC-5): docker must be on PATH — fail open otherwise.
  command -v docker >/dev/null 2>&1 || return 0

  # Reuse the exact pinned digest + eidolons.project slug (see header note).
  local image_ref slug
  image_ref="$(jq -r '(.mcpServers["atlas-aci"].args // [])[]
    | select(startswith("ghcr.io/") and contains("@sha256:"))' "$mcp" 2>/dev/null | head -1)"
  [ -n "$image_ref" ] || return 0
  slug="$(jq -r '(.mcpServers["atlas-aci"].args // [])[]
    | select(startswith("eidolons.project="))' "$mcp" 2>/dev/null | head -1)"
  slug="${slug#eidolons.project=}"
  [ -n "$slug" ] || return 0

  local cname="atlas-aci-sync-${slug}"

  # Per-turn call budget (s) — see header note (with_timeout, 1.5s, mirrors
  # lib_context.sh's ECM_MEMORY_TIMEOUT_S hot-path bound). Overridable for
  # tests / unusually slow hosts.
  local _atlas_sync_timeout="${EIDOLONS_ATLAS_SYNC_TIMEOUT_S:-1.5}"

  # Dedup (AC-4): skip the spawn if a container by this name already exists.
  # Bounded via with_timeout (lib.sh) — a wedged-but-up daemon must not hang
  # the turn; on timeout (rc=124) `running` is empty and we fall through to
  # the (also-bounded) spawn attempt below, backstopped by --name uniqueness.
  local running
  running="$(with_timeout "$_atlas_sync_timeout" docker ps -a --filter "name=^/${cname}\$" --format '{{.Names}}' 2>/dev/null || true)"
  printf '%s\n' "$running" | grep -qx "$cname" && return 0

  # Spawn detached (AC-3/AC-5). --pull=never: never block a turn on a pull;
  # rely on the already-local serve image (see header note above). Also
  # wrapped in with_timeout — cheap and consistent even though -d + --pull=
  # never already bound this to container-creation time in the common case.
  with_timeout "$_atlas_sync_timeout" docker run --rm -d --pull=never \
    --name "$cname" \
    --label "eidolons.project=${slug}" \
    -v "${root}:/repo" \
    --cap-drop ALL --security-opt no-new-privileges \
    "$image_ref" \
    index --repo /repo --since auto >/dev/null 2>&1 || true

  return 0
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

  # ── atlas-aci auto-sync (AC-6): fires on BOTH SessionStart and
  # UserPromptSubmit, independent of routing decision/mode — the whole point
  # is a per-turn background reindex regardless of whether a route occurs.
  # Output-silent (redirected) and error-silent (`|| true`) on top of its own
  # internal fail-open gates.
  if [[ "$event_name" == "SessionStart" || "$event_name" == "UserPromptSubmit" ]]; then
    _atlas_autosync >/dev/null 2>&1 || true
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
Lines tagged [skill/...] are verified procedural skills — prefer invoking them over re-deriving the procedure.
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

    # ── ECM P1 (T-F): context-policy block — pin re-inject + handoff digest ──
    # Opt-in (P0-1/AC-15): only when THIS project's eidolons.yaml declares a
    # 'context:' block — the nexus-shipped roster/pins.yaml is config, not a
    # per-project signal. The SessionStart matcher already covers every
    # source (startup|resume|clear|compact, FINDING-008) — pin naming and
    # handoff recall are idempotent and harmless on any cold start, so this
    # fires on all four sources rather than gating narrowly on
    # source=="compact" (a superset of the literal "post-compact only"
    # reading, never a narrower one; no stdin payload is read in
    # session_start mode today to discriminate source).
    if _ecm_project_enabled; then
      local ecm_pins ecm_handoff ecm_block
      ecm_pins="$(_ecm_pins_reminder)"
      ecm_handoff="$(_ecm_handoff_digest)"
      if [[ -n "$ecm_pins" || -n "$ecm_handoff" ]]; then
        ecm_block="## Context policy"
        [[ -n "$ecm_pins" ]] && ecm_block="${ecm_block}
Pins (must survive compaction/handoff): ${ecm_pins}."
        [[ -n "$ecm_handoff" ]] && ecm_block="${ecm_block}
Prior session handoff (session_handoff): ${ecm_handoff}"
        cortex_digest="${cortex_digest}

${ecm_block}"
      fi
    fi

    # Emit JSON.
    jq -n \
      --arg en "SessionStart" \
      --arg ctx "$cortex_digest" \
      '{"hookSpecificOutput": {"hookEventName": $en, "additionalContext": $ctx}}'
    return 0
  fi

  # ── PostToolUse mode (ECM P1, T-F): meter refresh; inject ONLY on a zone
  # transition (evidence C6). Most firings are silent, cheap sidecar
  # refreshes — no injection, no cost to the cache-discipline C-1/C-4 rules.
  if [[ "$hook_mode" == "post_tool_use" ]]; then
    _ecm_project_enabled || return 0  # opt-in gate (P0-1/AC-15)
    local ptu_stdin="${HOOK_STDIN_INPUT:-}"
    [[ -n "$ptu_stdin" ]] || return 0

    local ecm_bin=""
    if ecm_bin="$(command -v eidolons 2>/dev/null)"; then
      :
    else
      ecm_bin="${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons"
      [[ -x "$ecm_bin" ]] || return 0
    fi

    local meter_path=".eidolons/.context/meter.json"
    local prev_zone="unknown"
    [[ -f "$meter_path" ]] && prev_zone="$(jq -r '.zone // "unknown"' "$meter_path" 2>/dev/null || echo unknown)"

    printf '%s' "$ptu_stdin" | "$ecm_bin" context status --stdin >/dev/null 2>&1 || return 0

    local new_zone="unknown"
    [[ -f "$meter_path" ]] && new_zone="$(jq -r '.zone // "unknown"' "$meter_path" 2>/dev/null || echo unknown)"

    [[ "$new_zone" == "$prev_zone" ]] && return 0  # no transition -> silent refresh only

    local ptu_ctx
    ptu_ctx="Context zone changed: ${prev_zone} -> ${new_zone}."
    ptu_ctx="$(printf '%s' "$ptu_ctx" | cut -c1-800)"
    jq -n \
      --arg en "PostToolUse" \
      --arg ctx "$ptu_ctx" \
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

  # ── Model tier line(s) — roster/routing.yaml tier ladder (light<standard<deep) ──
  # Derived from the SAME artifact JSON parsed above (no kernel re-run). Single
  # dispatch/refusal-reroute → "model tier: <t>"; chain → arrow-joined per-step
  # "<eidolon>=<tier>" pairs aligned to .chain order. Fail-open: absent, empty,
  # length-mismatched, or non-string tier values ⇒ jq emits nothing and no line
  # (nor the fixed instruction line) is added — never breaks the JSON contract.
  local tier_line
  tier_line="$(printf '%s' "$artifact_json" | jq -r '
    (.chain // []) as $c
    | (.model_tier_per_step // []) as $mt
    | if ($c | length) == 0 or ($mt | length) == 0 or (($c | length) != ($mt | length))
        or ([$mt[] | select((type != "string") or (. == ""))] | length) > 0
      then empty
      elif ($c | length) == 1
      then "model tier: " + $mt[0]
      else "model tiers: "
           + ([range(0; $c | length) | ($c[.].eidolon // "?") + "=" + $mt[.]] | join(" → "))
      end
  ' 2>/dev/null || true)"

  if [[ -n "$tier_line" ]]; then
    ctx_text="$ctx_text  $tier_line  When dispatching subagents, honor each step's model tier (light<standard<deep) via the host's model selection mechanism; tiers come from roster/routing.yaml."
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

  # ── ECM P1 (T-F, AC-12): meter-zone + policy-verdict line ─────────────────
  # Opt-in (P0-1/AC-15): only when THIS project's eidolons.yaml declares a
  # 'context:' block. Hard-bounded to <=200 tokens (injected_artifact_max_tokens,
  # C-4) via its OWN cut -c1-800, independent of the overall 4000-char
  # ctx_text trim below. Reuses the SAME stdin payload run.sh already
  # captured for this firing (HOOK_STDIN_INPUT) so 'context status' can read
  # transcript_path (C7) without a second stdin read. Fail-open: absent
  # binary/meter/policy -> no line.
  local ecm_bin=""
  if _ecm_project_enabled && ecm_bin="$(command -v eidolons 2>/dev/null)"; then
    :
  elif _ecm_project_enabled; then
    ecm_bin="${EIDOLONS_HOME:-$HOME/.eidolons}/nexus/cli/eidolons"
    [[ -x "$ecm_bin" ]] || ecm_bin=""
  fi
  if [[ -n "$ecm_bin" ]]; then
    local ecm_status_json
    ecm_status_json="$(printf '%s' "${HOOK_STDIN_INPUT:-}" | "$ecm_bin" context status --stdin --json 2>/dev/null || true)"
    if [[ -n "$ecm_status_json" ]]; then
      local ecm_zone ecm_util ecm_verdict_json
      ecm_zone="$(printf '%s' "$ecm_status_json" | jq -r '.zone // "unknown"' 2>/dev/null || echo unknown)"
      ecm_util="$(printf '%s' "$ecm_status_json" | jq -r '.utilization // "null"' 2>/dev/null || echo null)"
      ecm_verdict_json="$("$ecm_bin" context policy --json 2>/dev/null || true)"
      if [[ -n "$ecm_verdict_json" ]]; then
        local ecm_op ecm_rule ecm_line
        ecm_op="$(printf '%s' "$ecm_verdict_json" | jq -r '.operation // "continue"' 2>/dev/null || echo continue)"
        ecm_rule="$(printf '%s' "$ecm_verdict_json" | jq -r '.rule // "?"' 2>/dev/null || echo "?")"
        ecm_line="Context: zone=${ecm_zone} util=${ecm_util} policy=${ecm_op}(${ecm_rule})."
        ecm_line="$(printf '%s' "$ecm_line" | cut -c1-800)"
        ctx_text="$ctx_text  $ecm_line"
      fi
    fi
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
