#!/usr/bin/env bash
# eidolons eval compliance — A/B routing-compliance instrument
# ═══════════════════════════════════════════════════════════════════════════
# Two-arm behavioral measurement: runs the same prompt corpus through a real
# headless host driver WITH (ARM A) and WITHOUT (ARM B) the harness wired,
# parses the stream-json for Task(<eidolon>) dispatches, and reports the
# delegation-rate delta + a GATE line vs the 80% FORGE reversal threshold
# (DOSSIER-HARNESS-2026-06.md:106).
#
# Design:
#   ARM A — full fixture (eidolons.yaml/lock + cortex + CLAUDE.md + agent stubs
#            + harness install → hooks live in .claude/settings.json)
#   ARM B — identical fixture MINUS harness install (prose cortex only)
#   Measures whether the mechanical hook injection raises delegation over the
#   prose-cortex baseline. Δ(A−B) is the harness effect; common-mode biases
#   (tool restriction, fixture shape) cancel in the difference.
#
# Adapter-not-engine stance: the nexus owns the HARNESS (fixtures, driver
# contract, stream parsing, metrics, gates). It embeds NO model. The model
# is supplied by --driver (default: claude -p). Live driver fires ONLY
# behind --yes. CI/bats always run --smoke (fake driver, zero network/model).
#
# ⚠ HONEST SCOPE: non-deterministic (model in loop). k=1 is NOISE for a
#   headline claim (Coder-7.5 lesson). Tool surface restricted to
#   Task/Read/Grep/Glob: the A−B delta is the harness effect (common-mode
#   bias cancels); absolute arm-A rate vs the 80% gate is a floor estimate
#   under a read-only surface.
#
# P0 constraints:
#   bash 3.2: no declare -A, no ${var,,}/${var^^}, no readarray/mapfile, no &>>
#   stdout = scorecard ONLY (text card or --json); all say/ok/info/warn/die → stderr
#   offline fixtures: NEVER fetch_eidolon/git clone in the builder
#   live driver gated behind --yes; CI never calls a live model

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

NEXUS_ROOT="$(cd "$(dirname "$ROSTER_FILE")/.." && pwd)"
DEFAULT_SUITE="$NEXUS_ROOT/evals/compliance-suite.yaml"

COMPLIANCE_VERSION="1.0"
DEFAULT_GATE_THRESHOLD=80
SESSION_TIMEOUT="${EIDOLONS_COMPLIANCE_SESSION_TIMEOUT:-120}"

usage() {
  cat >&2 <<EOF
eidolons eval compliance — A/B routing-compliance instrument

Usage: eidolons eval compliance [OPTIONS]

Options:
  --suite-file PATH    Suite YAML (default: evals/compliance-suite.yaml).
  --driver CMD         Driver command. Receives prompt on argv and stdin;
                       emits stream-json (one JSON object per line) to stdout.
                       Default: built-in claude -p invocation.
  --model NAME         Model for the default claude driver (default: sonnet).
  --max-turns N        Per-session turn cap (default: 3).
  --k N                Repeat each (prompt x arm) N times (default: 1).
                       k=1 is NOISE for a headline claim. Use k>=2 for a
                       stability signal.
  --arm A|B|both       Which arm(s) to run (default: both).
  --smoke              Run whole pipeline against the FAKE driver (canned
                       fixtures). No model, no network. CI/bats path.
                       Implies fake driver; ignores --driver/--model.
  --dry-run            Build fixtures + print cost envelope and exit 0
                       WITHOUT calling any driver.
  --yes                Confirm a LIVE billed run. Required for any non-smoke,
                       non-dry-run invocation.
  --keep               Keep the mktemp fixture projects (default: cleaned up).
  --min N              Exit 1 if ARM-A correct_target_rate < N percent.
  --gate               Print GATE line vs 80% and exit 1 if arm-A
                       correct_target_rate < 80%.
  --validate-suite     Self-test the suite shape and exit (no execution).
  --json               Emit the scorecard as JSON (stdout).
  --capture-sample     Under --keep, each session's raw stream is saved to
                       <fixture>/.eidolons/compliance/last-stream.jsonl.
                       Also enabled automatically under --keep.
  -h, --help           Show this help.

ARM A (treatment): full fixture + harness install (hooks in settings.json).
ARM B (control):   identical fixture MINUS harness install (prose cortex only).
Δ(A−B) is the harness effect. The FORGE reversal condition (dossier:106):
advisory compliance <80% correct_target_rate on T3 → escalate to block.

Modes:
  --smoke    FAKE driver (CI/bats). No model, no network, deterministic.
  --dry-run  Preview cost envelope. No driver calls.
  --yes      Live run. Billed. Requires explicit confirmation.
EOF
}

# ── Flags ──────────────────────────────────────────────────────────────────
SUITE="$DEFAULT_SUITE"
DRIVER_CMD=""
MODEL="sonnet"
MAX_TURNS=3
K=1
ARM="both"
SMOKE=false
DRY_RUN=false
YES=false
KEEP=false
MIN=""
GATE=false
VALIDATE=false
OUT="text"
CAPTURE_SAMPLE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite-file)     SUITE="${2:-}"; shift 2 ;;
    --driver)         DRIVER_CMD="${2:-}"; shift 2 ;;
    --model)          MODEL="${2:-sonnet}"; shift 2 ;;
    --max-turns)      MAX_TURNS="${2:-3}"; shift 2 ;;
    --k)              K="${2:-1}"; shift 2 ;;
    --arm)            ARM="${2:-both}"; shift 2 ;;
    --smoke)          SMOKE=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --yes)            YES=true; shift ;;
    --keep)           KEEP=true; CAPTURE_SAMPLE=true; shift ;;
    --min)            MIN="${2:-}"; shift 2 ;;
    --gate)           GATE=true; shift ;;
    --validate-suite) VALIDATE=true; shift ;;
    --json)           OUT="json"; shift ;;
    --capture-sample) CAPTURE_SAMPLE=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                die "Unknown option: $1 (see 'eidolons eval compliance --help')" ;;
  esac
done

# ── Arg validation ──────────────────────────────────────────────────────────
[[ "$MAX_TURNS" -ge 1 ]] 2>/dev/null || die "--max-turns must be >= 1"
[[ "$K" -ge 1 ]] 2>/dev/null || die "--k must be >= 1"
case "$ARM" in A|B|both) ;; *) die "--arm must be A, B, or both" ;; esac
[[ -n "$MIN" ]] && { [[ "$MIN" -ge 0 ]] 2>/dev/null || die "--min must be a non-negative integer"; }

[[ -f "$SUITE" ]] || die "Suite file not found: $SUITE"
suite_json="$(yaml_to_json "$SUITE")" || die "Could not parse suite YAML: $SUITE"

# --smoke + --yes: smoke wins, warn
if [[ "$SMOKE" == true && "$YES" == true ]]; then
  warn "--yes is ignored under --smoke (fake driver runs no model)"
  YES=false
fi

# Custom driver validation (non-smoke path): fail early if driver is not executable
if [[ "$SMOKE" == false && -n "$DRIVER_CMD" ]]; then
  # DRIVER_CMD may be a path or a shell invocation; extract the first word
  _driver_bin="$(printf '%s' "$DRIVER_CMD" | awk '{print $1}')"
  if [[ -n "$_driver_bin" ]]; then
    if ! command -v "$_driver_bin" >/dev/null 2>&1 && [[ ! -x "$_driver_bin" ]]; then
      die "custom driver not found or not executable: '$_driver_bin'. Check --driver argument."
    fi
  fi
fi

# ── Capability classes (the 8 recognized + control) ─────────────────────────
KNOWN_CLASSES="scout planner coder scriber reasoner debugger executor control"

# ── ALL FUNCTIONS DEFINED BEFORE FIRST CALL ───────────────────────────────
# (bash 3.2: functions must be defined before any top-level code calls them)

# ── _validate_suite ──────────────────────────────────────────────────────────
_validate_suite() {
  local problems=""

  # Check required fields + class values + no dup ids/prompts
  problems="$(printf '%s' "$suite_json" | jq -r --arg known "$KNOWN_CLASSES" '
    [ .tasks // [] | to_entries[] | .key as $i | .value as $t |
      (if ($t.id // "") == "" then "task[\($i)]: missing id" else empty end),
      (if ($t.prompt // "") == "" then "task[\($i)]: missing prompt" else empty end),
      (if ($t.class // "") == "" then "task[\($i)]: missing class" else empty end),
      (if ($t.class // "") != "" then
         ($known | split(" ")) as $kc |
         if ($kc | index($t.class)) == null then "task[\($i)] id=\($t.id // "?"): unknown class \($t.class)" else empty end
       else empty end)
    ] | .[]
  ' 2>/dev/null || true)"

  # Duplicate ids
  local dup_ids
  dup_ids="$(printf '%s' "$suite_json" | jq -r '
    [.tasks[].id] | group_by(.) | map(select(length>1)) | .[] | "duplicate id: \(.[0])"
  ' 2>/dev/null || true)"
  [[ -n "$dup_ids" ]] && problems="$(printf '%s\n%s' "$problems" "$dup_ids")"

  # Duplicate prompts
  local dup_prompts
  dup_prompts="$(printf '%s' "$suite_json" | jq -r '
    [.tasks[].prompt] | group_by(.) | map(select(length>1)) | .[] | "duplicate prompt: \(.[0])"
  ' 2>/dev/null || true)"
  [[ -n "$dup_prompts" ]] && problems="$(printf '%s\n%s' "$problems" "$dup_prompts")"

  # Coverage: at least one task per capability class (excluding control) + >=2 controls
  local missing_classes=""
  for cls in scout planner coder scriber reasoner debugger executor; do
    local cnt
    cnt="$(printf '%s' "$suite_json" | jq --arg c "$cls" '[.tasks[] | select(.class == $c)] | length')"
    [[ "$cnt" -eq 0 ]] && missing_classes="${missing_classes}${cls} "
  done
  [[ -n "$missing_classes" ]] && problems="$(printf '%s\nmissing coverage for classes: %s' "$problems" "${missing_classes}")"

  local n_controls
  n_controls="$(printf '%s' "$suite_json" | jq '[.tasks[] | select(.control == true or .class == "control")] | length')"
  [[ "$n_controls" -lt 2 ]] && problems="$(printf '%s\nneed >= 2 control tasks (found %s)' "$problems" "$n_controls")"

  # Cross-check: for tasks marked control:true, validate kernel agrees (clarify)
  if [[ -f "$SELF_DIR/run.sh" ]]; then
    local ctrl_ids
    ctrl_ids="$(printf '%s' "$suite_json" | jq -r '.tasks[] | select(.control == true or .class == "control") | .id')"
    while IFS= read -r cid; do
      [[ -z "$cid" ]] && continue
      local cprompt cgt_decision
      cprompt="$(printf '%s' "$suite_json" | jq -r --arg id "$cid" '.tasks[] | select(.id == $id) | .prompt')"
      cgt_decision="$(bash "$SELF_DIR/run.sh" "$cprompt" --json 2>/dev/null | jq -r '.decision' 2>/dev/null || echo "unknown")"
      if [[ "$cgt_decision" != "clarify" ]]; then
        problems="$(printf '%s\ncontrol task %s: kernel routes to dispatch/chain (decision=%s); re-check the control flag or prompt' "$problems" "$cid" "$cgt_decision")"
      fi
    done <<< "$ctrl_ids"
  fi

  problems="$(printf '%s\n' "$problems" | grep -v '^[[:space:]]*$' || true)"
  local n_tasks
  n_tasks="$(printf '%s' "$suite_json" | jq '.tasks | length')"

  if [[ -z "$problems" ]]; then
    if [[ "$OUT" == "json" ]]; then
      jq -nc "{valid:true,problems:[],n_tasks:${n_tasks}}"
    else
      ok "compliance suite valid (${n_tasks} tasks)"
    fi
    return 0
  else
    if [[ "$OUT" == "json" ]]; then
      jq -nc --arg p "$problems" '{valid:false,problems:($p|split("\n")|map(select(length>0)))}'
    else
      warn "compliance suite invalid:"
      printf '%s\n' "$problems" | grep -v '^$' | while IFS= read -r line; do
        printf '  - %s\n' "$line" >&2
      done
    fi
    return 1
  fi
}

# ── _build_fixture ARM DEST ───────────────────────────────────────────────
# Build an offline deterministic fixture project in $DEST.
# ARM = A or B. ARM A gets harness install on top; ARM B does not.
_build_fixture() {
  local arm="$1"
  local dest="$2"

  mkdir -p "$dest/.eidolons/cortex" "$dest/.claude/agents" "$dest/.eidolons/compliance"

  # 1. Cortex: copy EIDOLONS.md from the checkout
  local cortex_src="$NEXUS_ROOT/EIDOLONS.md"
  [[ -f "$cortex_src" ]] || die "EIDOLONS.md not found at $cortex_src — nexus checkout is broken; refusing to build fixtures."
  cp "$cortex_src" "$dest/.eidolons/cortex/EIDOLONS.md"

  # 2. eidolons.yaml (minimal, all roster members, version 0.0.0)
  {
    printf 'version: 1\n'
    printf 'hosts:\n'
    printf '  wire: [claude-code]\n'
    printf '  shared_dispatch: true\n'
    printf 'members:\n'
    local rnames
    rnames="$(roster_list_names)"
    while IFS= read -r rname; do
      [[ -z "$rname" ]] && continue
      local srepo
      srepo="$(roster_get "$rname" | jq -r '.source.repo // empty')"
      printf '  - { name: %s, version: "0.0.0", source: github:%s }\n' "$rname" "$srepo"
    done <<< "$rnames"
  } > "$dest/eidolons.yaml"

  # 3. eidolons.lock (minimal — enough for harness install)
  local gen_at
  gen_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-01-01T00:00:00Z")"
  {
    printf 'generated_at: "%s"\n' "$gen_at"
    printf 'eidolons_cli_version: "0.0.0"\n'
    printf 'nexus_commit: "compliance-fixture"\n'
    printf 'hosts:\n'
    printf '  wire: [claude-code]\n'
    printf 'members:\n'
    local rnames2
    rnames2="$(roster_list_names)"
    while IFS= read -r rname; do
      [[ -z "$rname" ]] && continue
      printf '  - name: %s\n' "$rname"
      printf '    version: "0.0.0"\n'
      printf '    resolved: "github:placeholder@0.0.0"\n'
      printf '    target: "./.eidolons/%s"\n' "$rname"
      printf '    hosts_wired: ["claude-code"]\n'
    done <<< "$rnames2"
  } > "$dest/eidolons.lock"

  # 4. CLAUDE.md — standard cortex pointer block (D-FIX-1: inline heredoc)
  cat > "$dest/CLAUDE.md" <<'CLAUDEMD'
# CLAUDE.md
<!-- eidolon:cortex start -->
## Eidolons routing cortex
Read `.eidolons/cortex/EIDOLONS.md` at session start. For any non-trivial
request, route through the Eidolons dispatch protocol: delegate to the
indicated Eidolon via the Task tool (subagent_type = the Eidolon name) rather
than acting in the main loop.
<!-- eidolon:cortex end -->
CLAUDEMD

  # 5. Agent stubs — one .claude/agents/<name>.md per roster member (D-FIX-2)
  # Load routing.yaml once to resolve suggested_tier → model string
  local routing_json
  routing_json="$(yaml_to_json "$NEXUS_ROOT/roster/routing.yaml" 2>/dev/null || echo '{}')"
  local profiles_json
  profiles_json="$(yaml_to_json "$NEXUS_ROOT/roster/model-profiles.yaml" 2>/dev/null || echo '{}')"
  local rnames3
  rnames3="$(roster_list_names)"
  while IFS= read -r rname; do
    [[ -z "$rname" ]] && continue
    local entry
    entry="$(roster_get "$rname")"
    local display
    display="$(printf '%s' "$entry" | jq -r '.display_name // .name')"
    # Truncate summary to ~200 chars
    local summary
    summary="$(printf '%s' "$entry" | jq -r '.methodology.summary // ""' | cut -c1-200)"
    # Resolve model: suggested_tier from routing.yaml → model-profiles.yaml anthropic profile
    local tier
    tier="$(printf '%s' "$routing_json" | jq -r --arg n "$rname" '.eidolons[$n].suggested_tier // "standard"')"
    local model_str
    model_str="$(printf '%s' "$profiles_json" | jq -r --arg t "$tier" '.profiles.anthropic.tiers[$t] // "sonnet"')"
    cat > "$dest/.claude/agents/${rname}.md" <<STUB
---
name: ${rname}
description: "${summary}"
model: ${model_str}
tools: Read, Grep, Glob
---
You are ${display}. (compliance-eval stub — full methodology not installed.)
When dispatched, acknowledge the route and stop.
STUB
  done <<< "$rnames3"

  # 6. .claude/settings.json — permissions allowlist (D-C2 exact spec)
  # Written FIRST; ARM A's harness install merges hooks on top (D-FIX-3).
  cat > "$dest/.claude/settings.json" <<'SETTINGS'
{
  "permissions": {
    "allow": [
      "Task",
      "Read",
      "Grep",
      "Glob"
    ],
    "deny": [],
    "defaultMode": "acceptEdits"
  }
}
SETTINGS

  # 7. ARM A only: run harness install (merges hooks into settings.json)
  # Skip if EIDOLONS_COMPLIANCE_SABOTAGE=skip-harness (test seam — D-TEST-1)
  if [[ "$arm" == "A" && "${EIDOLONS_COMPLIANCE_SABOTAGE:-}" != "skip-harness" ]]; then
    (
      cd "$dest"
      EIDOLONS_SKIP_REFRESH=1 \
      EIDOLONS_NEXUS="$NEXUS_ROOT" \
        bash "$SELF_DIR/harness_install.sh" \
        --hosts claude-code \
        --non-interactive \
        --force \
        2>/dev/null
    ) || warn "harness install returned non-zero for ARM A fixture (self-check will catch broken wiring)"
  fi
}

# ── _arm_a_selfcheck DEST ────────────────────────────────────────────────────
# Verifies ARM A is properly wired before measuring. Aborts the WHOLE run
# if any check fails (D-C8 — no vacuous arms).
_arm_a_selfcheck() {
  local dest="$1"

  # Check 1: hooks in settings.json
  local has_hooks
  has_hooks="$(jq -r 'if (.hooks.UserPromptSubmit and .hooks.SessionStart) then "yes" else "no" end' \
    "$dest/.claude/settings.json" 2>/dev/null || echo "no")"
  if [[ "$has_hooks" != "yes" ]]; then
    die "ARM-A wiring self-check failed: .hooks.UserPromptSubmit/.hooks.SessionStart not present in .claude/settings.json. The instrument is broken; refusing to report a vacuous comparison. Run 'eidolons harness status' in the fixture or 'eidolons doctor'."
  fi

  # Check 2: shims executable
  local shim_ups="$dest/.eidolons/harness/hooks/claude-code-UserPromptSubmit.sh"
  local shim_ss="$dest/.eidolons/harness/hooks/claude-code-SessionStart.sh"
  if [[ ! -x "$shim_ups" || ! -x "$shim_ss" ]]; then
    die "ARM-A wiring self-check failed: harness shims not executable ($shim_ups, $shim_ss). The instrument is broken; refusing to report a vacuous comparison. Run 'eidolons harness status' in the fixture or 'eidolons doctor'."
  fi

  # Check 3: kernel returns a route for the probe prompt
  local probe_result
  probe_result="$(echo '{"prompt":"map the auth flow"}' \
    | EIDOLONS_NEXUS="$NEXUS_ROOT" bash "$SELF_DIR/run.sh" --hook claude-code --stdin \
    2>/dev/null || echo '{}')"
  local has_route
  has_route="$(printf '%s' "$probe_result" \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")"
  if ! printf '%s' "$has_route" | grep -q 'Route:'; then
    die "ARM-A wiring self-check failed: kernel probe did not return a Route: in hookSpecificOutput.additionalContext (got: '${has_route}'). The instrument is broken; refusing to report a vacuous comparison. Run 'eidolons harness status' in the fixture or 'eidolons doctor'."
  fi

  return 0
}

# ── _parse_stream STREAM ROSTER_NAMES ────────────────────────────────────────
# Parse NDJSON stream for Task tool_use events.
# Outputs JSON array: [{subagent_type, turn}] sorted by turn.
_parse_stream() {
  local stream="$1"
  local roster_names="$2"  # JSON array of strings

  printf '%s\n' "$stream" | jq -c -R 'fromjson? // empty' \
    | jq -s -c --argjson roster "$roster_names" '
      [ to_entries[]
        | .key as $turn
        | .value as $ev
        # Tool_use blocks may live at .message.content[] or .content[] (D-PARSE-1)
        | ( ($ev.message.content // $ev.content // [])
            | if type == "array" then . else [] end )[]
        | select((.type? == "tool_use") and (.name? == "Task"))
        | (.input.subagent_type // .input.subagentType // null) as $st
        | select($st != null)
        | select($roster | index($st) != null)
        | { subagent_type: $st, turn: $turn }
      ]
    ' 2>/dev/null || echo '[]'
}

# ── _score_prompt GT_DECISION GT_SELECTED PARSED IS_CONTROL ─────────────────
# Returns JSON: {delegated_any, delegated_correct}
_score_prompt() {
  local gt_decision="$1"
  local gt_selected="$2"  # JSON array
  local parsed="$3"       # JSON array from _parse_stream
  local is_control="$4"   # "true" or "false"

  if [[ "$is_control" == "true" ]]; then
    # Control: correct = NO Task dispatch
    local dispatched
    dispatched="$(printf '%s' "$parsed" | jq 'length > 0')"
    if [[ "$dispatched" == "false" ]]; then
      printf '{"delegated_any":false,"delegated_correct":true}'
    else
      printf '{"delegated_any":true,"delegated_correct":false}'
    fi
    return
  fi

  # Routed prompt: delegated_any = >=1 Task to any roster Eidolon
  local n_dispatched
  n_dispatched="$(printf '%s' "$parsed" | jq 'length')"

  if [[ "$n_dispatched" -eq 0 ]]; then
    printf '{"delegated_any":false,"delegated_correct":false}'
    return
  fi

  # delegated_correct: first Task's subagent_type in kernel's selected
  # For chain: chain head = selected[0]; the first dispatch must match it
  local first_agent
  first_agent="$(printf '%s' "$parsed" | jq -r '.[0].subagent_type')"
  local in_selected
  in_selected="$(printf '%s' "$gt_selected" | jq --arg a "$first_agent" 'index($a) != null')"

  printf '{"delegated_any":true,"delegated_correct":%s}' "$in_selected"
}

# ── _fake_driver PROMPT ───────────────────────────────────────────────────────
# Returns stream NDJSON from canned fixtures based on the prompt content.
# Smoke mode uses this instead of the real claude driver.
_fake_driver() {
  local prompt="$1"
  local fixture_dir="$SELF_DIR/../tests/fixtures/compliance"
  # Resolve to abs path
  fixture_dir="$(cd "$fixture_dir" 2>/dev/null && pwd || echo "$SELF_DIR/../tests/fixtures/compliance")"

  # Map prompt keywords → fixture file
  # The smoke suite is engineered so these mappings cover all parser branches.
  local plow
  plow="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"

  local fixture_file=""
  case "$plow" in
    *"map the auth"*|*"map the authentication"*)
      fixture_file="$fixture_dir/dispatch-correct.jsonl" ;;
    *"trace who calls"*)
      fixture_file="$fixture_dir/dispatch-correct.jsonl" ;;
    *"spec out"*)
      fixture_file="$fixture_dir/chain-head.jsonl" ;;
    *"design the requirements"*|*"design and implement"*)
      fixture_file="$fixture_dir/chain-head.jsonl" ;;
    *"implement the retry"*)
      fixture_file="$fixture_dir/dispatch-wrong.jsonl" ;;
    *"fix the off-by-one"*)
      fixture_file="$fixture_dir/dispatch-correct.jsonl" ;;
    *"document the auth"*)
      fixture_file="$fixture_dir/dispatch-correct.jsonl" ;;
    *"write a runbook"*)
      fixture_file="$fixture_dir/dispatch-correct.jsonl" ;;
    *"which approach"*)
      fixture_file="$fixture_dir/dispatch-correct.jsonl" ;;
    *"stack trace"*)
      fixture_file="$fixture_dir/dispatch-correct.jsonl" ;;
    *"fix the typo"*)
      fixture_file="$fixture_dir/dispatch-correct.jsonl" ;;
    *"do the thing"*)
      fixture_file="$fixture_dir/control-clean.jsonl" ;;
    *"can you help"*)
      fixture_file="$fixture_dir/control-clean.jsonl" ;;
    *)
      fixture_file="$fixture_dir/no-task.jsonl" ;;
  esac

  if [[ -f "$fixture_file" ]]; then
    cat "$fixture_file"
  else
    # Fallback: no-task
    cat "$fixture_dir/no-task.jsonl" 2>/dev/null || \
      echo '{"type":"assistant","message":{"content":[{"type":"text","text":"no fixture"}]},"index":0}'
  fi
}

# ── _run_driver PROMPT FIXTURE_DIR ───────────────────────────────────────────
# Runs the driver for a single session. Returns NDJSON stream on stdout.
# Handles timeout; timeout = empty stream (caller treats as no-dispatch).
_run_driver() {
  local prompt="$1"
  local fixture_dir="$2"

  if [[ "$SMOKE" == true ]]; then
    _fake_driver "$prompt"
    # Under --keep / --capture-sample in smoke mode: save stream
    if [[ "$CAPTURE_SAMPLE" == true ]]; then
      local stream_dir="$fixture_dir/.eidolons/compliance"
      mkdir -p "$stream_dir"
      _fake_driver "$prompt" > "$stream_dir/last-stream.jsonl"
    fi
    return
  fi

  # Live path: check for claude binary before first call
  if [[ -z "$DRIVER_CMD" ]]; then
    command -v claude >/dev/null 2>&1 || die \
"the default driver needs the 'claude' binary on PATH and it is absent.
Install Claude Code, or pass --driver <cmd> to substitute another host,
or run --smoke for the fake-driver pipeline."
  fi

  # Hard safety net: the test/CI harness exports EIDOLONS_COMPLIANCE_NO_LIVE=1
  # so a test that forgets --smoke (or mis-scrubs PATH) can NEVER spawn a real,
  # billed default-claude session. The instrument fails loud, never silently
  # bills. Only the default-claude path is netted; explicit --driver cmds in
  # tests are fakes and harmless. Live runs happen via the runbook, not bats.
  if [[ "${EIDOLONS_COMPLIANCE_NO_LIVE:-}" == "1" && -z "$DRIVER_CMD" ]]; then
    die \
"refusing to invoke the live 'claude' driver: EIDOLONS_COMPLIANCE_NO_LIVE=1 is set
(test/CI safety net). Use --smoke for the fake-driver pipeline, or unset the
variable for a real, billed measurement run (see runbook-compliance.md)."
  fi

  export EIDOLONS_COMPLIANCE_PROMPT="$prompt"
  export EIDOLONS_COMPLIANCE_CWD="$fixture_dir"

  local stream=""
  local rc=0

  if [[ -n "$DRIVER_CMD" ]]; then
    # Custom driver: pass prompt on argv and stdin
    stream="$(
      cd "$fixture_dir"
      printf '%s' "$prompt" | with_timeout "$SESSION_TIMEOUT" bash -c "$DRIVER_CMD \"\$EIDOLONS_COMPLIANCE_PROMPT\"" 2>/dev/null
    )" || rc=$?
  else
    # Default: claude -p
    stream="$(
      cd "$fixture_dir"
      printf '%s' "$prompt" | with_timeout "$SESSION_TIMEOUT" \
        claude -p "$prompt" \
          --output-format stream-json \
          --verbose \
          --max-turns "$MAX_TURNS" \
          --model "$MODEL" \
        2>/dev/null
    )" || rc=$?
  fi

  # rc=124 = timeout (with_timeout convention); treat as empty stream
  if [[ "$rc" -eq 124 ]]; then
    warn "session timed out after ${SESSION_TIMEOUT}s (prompt: '${prompt:0:60}...')"
    stream=""
  fi

  # Under --keep / --capture-sample: save raw stream
  if [[ "$CAPTURE_SAMPLE" == true ]]; then
    local stream_dir="$fixture_dir/.eidolons/compliance"
    mkdir -p "$stream_dir"
    printf '%s\n' "$stream" > "$stream_dir/last-stream.jsonl"
  fi

  printf '%s\n' "$stream"
}

# ── _aggregate_arm RESULTS HARNESS_BOOL ──────────────────────────────────────
# Compute per-arm metrics from the per-prompt results array.
_aggregate_arm() {
  local results="$1"
  local harness_bool="$2"

  # Routed and control sets
  local n_routed n_control
  n_routed="$(printf '%s' "$results" | jq '[.[] | select(.control == false)] | length')"
  n_control="$(printf '%s' "$results" | jq '[.[] | select(.control == true)] | length')"

  # delegation_rate: routed prompts with delegated_any=true (pass@1 over k)
  local deleg_n
  deleg_n="$(printf '%s' "$results" | jq '[.[] | select(.control == false and .delegated_any == true)] | length')"
  local delegation_rate
  delegation_rate="$(jq -n --argjson n "$deleg_n" --argjson t "$n_routed" 'if $t == 0 then 0 else ($n/$t) end')"

  # correct_target_rate: routed prompts with delegated_correct=true (pass@1)
  local correct_n
  correct_n="$(printf '%s' "$results" | jq '[.[] | select(.control == false and .delegated_correct == true)] | length')"
  local correct_target_rate
  correct_target_rate="$(jq -n --argjson n "$correct_n" --argjson t "$n_routed" 'if $t == 0 then 0 else ($n/$t) end')"

  # control_pass_rate: control prompts delegated_correct=true in ALL k (pass^k)
  local ctrl_pass_n
  ctrl_pass_n="$(printf '%s' "$results" | jq '[.[] | select(.control == true and .correct_all_k == true)] | length')"
  local control_pass_rate
  control_pass_rate="$(jq -n --argjson n "$ctrl_pass_n" --argjson t "$n_control" 'if $t == 0 then 0 else ($n/$t) end')"

  # stability_passk: routed prompts correct in ALL k
  local stab_n
  stab_n="$(printf '%s' "$results" | jq '[.[] | select(.control == false and .correct_all_k == true)] | length')"
  local stability_passk
  stability_passk="$(jq -n --argjson n "$stab_n" --argjson t "$n_routed" 'if $t == 0 then 0 else ($n/$t) end')"

  # per-class breakdown (group_by on plain array — works on empty array too)
  local by_class
  by_class="$(printf '%s' "$results" | jq -c '
    group_by(.class) |
    map({
      class: .[0].class,
      delegation_rate: (
        if ([.[] | select(.control == false)] | length) == 0 then 0
        else (
          ([.[] | select(.control == false and .delegated_any == true)] | length) /
          ([.[] | select(.control == false)] | length)
        )
        end
      ),
      correct_target_rate: (
        if ([.[] | select(.control == false)] | length) == 0 then 0
        else (
          ([.[] | select(.control == false and .delegated_correct == true)] | length) /
          ([.[] | select(.control == false)] | length)
        )
        end
      )
    })
  ')"

  jq -nc \
    --argjson harness "$harness_bool" \
    --argjson dr "$delegation_rate" \
    --argjson ctr "$correct_target_rate" \
    --argjson cpr "$control_pass_rate" \
    --argjson spk "$stability_passk" \
    --argjson bc "$by_class" \
    --argjson pp "$results" \
    '{harness:$harness, delegation_rate:$dr, correct_target_rate:$ctr,
      control_pass_rate:$cpr, stability_passk:$spk,
      by_class:$bc, per_prompt:$pp}'
}

# ── _run_arm ARM FIXTURE_DIR RESULTS_FILE ────────────────────────────────────
_run_arm() {
  local arm="$1"
  local fixture_dir="$2"
  local results_file="$3"

  local arm_results="[]"
  local task_ids_arm
  task_ids_arm="$(printf '%s' "$suite_json" | jq -r '.tasks[].id')"

  while IFS= read -r tid; do
    [[ -z "$tid" ]] && continue
    local arm_task arm_prompt arm_class arm_is_ctrl
    arm_task="$(printf '%s' "$suite_json" | jq -c --arg id "$tid" '.tasks[] | select(.id == $id)')"
    arm_prompt="$(printf '%s' "$arm_task" | jq -r '.prompt')"
    arm_class="$(printf '%s' "$arm_task" | jq -r '.class // "unknown"')"
    arm_is_ctrl="$(printf '%s' "$arm_task" | jq -r 'if (.control == true or .class == "control") then "true" else "false" end')"

    local gt_entry gt_decision gt_selected
    gt_entry="$(printf '%s' "$GT_MAP" | jq -c --arg id "$tid" '.[$id] // {decision:"clarify",selected:[],control:false}')"
    gt_decision="$(printf '%s' "$gt_entry" | jq -r '.decision')"
    gt_selected="$(printf '%s' "$gt_entry" | jq -c '.selected')"

    local delegated_any_ever=false
    local delegated_correct_ever=false
    local correct_all_k=true
    local k_correct=0
    local k_runs=0
    local last_observed="[]"

    for k_idx in $(seq 1 "$K"); do
      k_runs=$((k_runs + 1))
      local stream observed score d_any d_correct
      stream="$(_run_driver "$arm_prompt" "$fixture_dir")"
      observed="$(_parse_stream "$stream" "$ROSTER_NAMES_JSON")"
      score="$(_score_prompt "$gt_decision" "$gt_selected" "$observed" "$arm_is_ctrl")"
      d_any="$(printf '%s' "$score" | jq -r '.delegated_any')"
      d_correct="$(printf '%s' "$score" | jq -r '.delegated_correct')"
      last_observed="$observed"

      [[ "$d_any" == "true" ]] && delegated_any_ever=true
      [[ "$d_correct" == "true" ]] && delegated_correct_ever=true
      [[ "$d_correct" == "false" ]] && correct_all_k=false
      [[ "$d_correct" == "true" ]] && k_correct=$((k_correct + 1))
    done

    local passk_str="${k_correct}/${k_runs}"
    arm_results="$(printf '%s' "$arm_results" | jq -c \
      --arg id "$tid" \
      --arg cls "$arm_class" \
      --argjson ctrl "$([ "$arm_is_ctrl" == "true" ] && echo true || echo false)" \
      --argjson gt "$gt_selected" \
      --argjson da "$([[ "$delegated_any_ever" == "true" ]] && echo true || echo false)" \
      --argjson dc "$([[ "$delegated_correct_ever" == "true" ]] && echo true || echo false)" \
      --argjson cak "$([[ "$correct_all_k" == "true" ]] && echo true || echo false)" \
      --arg pk "$passk_str" \
      --argjson obs "$last_observed" \
      '. + [{id:$id, class:$cls, control:$ctrl, ground_truth:$gt,
             delegated_any:$da, delegated_correct:$dc, correct_all_k:$cak,
             passk_correct:$pk, observed:$obs}]')"
  done <<< "$task_ids_arm"

  printf '%s' "$arm_results" > "$results_file"
}

# ──────────────────────────────────────────────────────────────────────────────
# END OF FUNCTION DEFINITIONS — execution starts here
# ──────────────────────────────────────────────────────────────────────────────

# ── --validate-suite (early exit, before fixtures) ──────────────────────────
if [[ "$VALIDATE" == true ]]; then
  _validate_suite
  exit $?
fi

# ── Live-run confirmation guard ──────────────────────────────────────────────
# If not smoke, not dry-run, and no --yes → die non-zero (D-COST-1).
if [[ "$SMOKE" == false && "$DRY_RUN" == false && "$YES" == false ]]; then
  n_tasks="$(printf '%s' "$suite_json" | jq '[.tasks[]] | length')"
  n_arms=1; [[ "$ARM" == "both" ]] && n_arms=2
  n_sessions=$(( n_tasks * n_arms * K ))
  printf '%s\n' "COST: ${n_tasks} prompts × ${n_arms} arm(s) × k=${K} = ${n_sessions} live sessions" >&2
  printf '%s\n' "      driver=claude -p  model=${MODEL}  max-turns=${MAX_TURNS}" >&2
  printf '%s\n' "      This calls a BILLED model. Re-run with --yes to proceed," >&2
  printf '%s\n' "      --dry-run to preview, or --smoke for the fake-driver pipeline." >&2
  die "live run requires --yes (this calls a billed model; ${n_sessions} sessions estimated). Use --smoke for the fake-driver pipeline or --dry-run to preview the cost."
fi

# ── Fixture directories (mktemp + cleanup trap) ──────────────────────────────
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/eidolons-compliance.XXXXXX")"
FIXTURE_A="$FIXTURE_ROOT/compliance-arm-A"
FIXTURE_B="$FIXTURE_ROOT/compliance-arm-B"
cleanup() {
  if [[ "$KEEP" == false ]]; then
    rm -rf "$FIXTURE_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ── Dry-run: print cost envelope and exit 0 ──────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  n_tasks="$(printf '%s' "$suite_json" | jq '[.tasks[]] | length')"
  n_arms=1; [[ "$ARM" == "both" ]] && n_arms=2
  n_sessions=$(( n_tasks * n_arms * K ))
  printf '%s\n' "COST: ${n_tasks} prompts × ${n_arms} arm(s) × k=${K} = ${n_sessions} live sessions" >&2
  printf '%s\n' "      driver=claude -p  model=${MODEL}  max-turns=${MAX_TURNS}" >&2
  printf '%s\n' "      (dry-run — no driver called)" >&2
  exit 0
fi

# ── Build fixtures ───────────────────────────────────────────────────────────
say "building compliance fixtures (offline, deterministic)..."

if [[ "$ARM" == "A" || "$ARM" == "both" ]]; then
  say "building ARM A fixture (with harness install)..."
  _build_fixture "A" "$FIXTURE_A"
fi
if [[ "$ARM" == "B" || "$ARM" == "both" ]]; then
  say "building ARM B fixture (no harness install)..."
  _build_fixture "B" "$FIXTURE_B"
fi

# ── ARM-A self-check (D-C8 — must run before measuring) ─────────────────────
if [[ "$ARM" == "A" || "$ARM" == "both" ]]; then
  say "ARM-A wiring self-check..."
  _arm_a_selfcheck "$FIXTURE_A"
  info "ARM-A wiring self-check: OK"
fi

# ── Print cost envelope (live path) ──────────────────────────────────────────
if [[ "$SMOKE" == false ]]; then
  n_tasks_cost="$(printf '%s' "$suite_json" | jq '[.tasks[]] | length')"
  n_arms_cost=1; [[ "$ARM" == "both" ]] && n_arms_cost=2
  n_sessions_cost=$(( n_tasks_cost * n_arms_cost * K ))
  printf '%s\n' "COST: ${n_tasks_cost} prompts × ${n_arms_cost} arm(s) × k=${K} = ${n_sessions_cost} live sessions" >&2
  printf '%s\n' "      driver=${DRIVER_CMD:-claude -p}  model=${MODEL}  max-turns=${MAX_TURNS}" >&2
fi

# ── Build roster names array (for parser filtering) ──────────────────────────
ROSTER_NAMES_JSON="$(roster_list_names | jq -R . | jq -s 'sort')"

# ── Compute ground truth ONCE per prompt (deterministic; cached) ─────────────
say "computing ground truth via kernel..."
GT_MAP="{}"
task_ids_all="$(printf '%s' "$suite_json" | jq -r '.tasks[].id')"
while IFS= read -r tid; do
  [[ -z "$tid" ]] && continue
  local_task="$(printf '%s' "$suite_json" | jq -c --arg id "$tid" '.tasks[] | select(.id == $id)')"
  local_prompt="$(printf '%s' "$local_task" | jq -r '.prompt')"
  local_is_ctrl="$(printf '%s' "$local_task" | jq -r 'if (.control == true or .class == "control") then "true" else "false" end')"

  # Build ctx flags
  gt_flags=()
  sm="$(printf '%s' "$local_task" | jq -r '.ctx.surface_modules // empty')"; [[ -n "$sm" ]] && gt_flags+=(--surface-modules "$sm")
  sf="$(printf '%s' "$local_task" | jq -r '.ctx.surface_files // empty')";   [[ -n "$sf" ]] && gt_flags+=(--surface-files "$sf")
  [[ "$(printf '%s' "$local_task" | jq -r '.ctx.trance // false')" == "true" ]] && gt_flags+=(--trance)
  [[ "$(printf '%s' "$local_task" | jq -r '.ctx.prior_failure // false')" == "true" ]] && gt_flags+=(--prior-failure)

  # Compute GT
  gt_raw="$(bash "$SELF_DIR/run.sh" "$local_prompt" ${gt_flags[@]+"${gt_flags[@]}"} --json 2>/dev/null || echo '{}')"
  gt_decision="$(printf '%s' "$gt_raw" | jq -r '.decision // "clarify"')"
  gt_selected="$(printf '%s' "$gt_raw" | jq -c '.selected // []')"

  # If suite says control, honour it
  if [[ "$local_is_ctrl" == "true" ]]; then
    gt_decision="clarify"
  fi

  GT_MAP="$(printf '%s' "$GT_MAP" | jq -c \
    --arg id "$tid" \
    --arg dec "$gt_decision" \
    --argjson sel "$gt_selected" \
    --arg ctrl "$local_is_ctrl" \
    '. + {($id): {decision: $dec, selected: $sel, control: ($ctrl == "true")}}')"
done <<< "$task_ids_all"

# ── Run loop ─────────────────────────────────────────────────────────────────
RESULTS_A="[]"
RESULTS_B="[]"

MODE_LABEL="smoke"; [[ "$SMOKE" == false ]] && MODE_LABEL="live"

say "running compliance sessions (mode=${MODE_LABEL}, k=${K}, arm=${ARM})..."

if [[ "$ARM" == "A" || "$ARM" == "both" ]]; then
  _run_arm "A" "$FIXTURE_A" "$FIXTURE_ROOT/results_A.json"
  RESULTS_A="$(cat "$FIXTURE_ROOT/results_A.json")"
fi
if [[ "$ARM" == "B" || "$ARM" == "both" ]]; then
  _run_arm "B" "$FIXTURE_B" "$FIXTURE_ROOT/results_B.json"
  RESULTS_B="$(cat "$FIXTURE_ROOT/results_B.json")"
fi

# ── Aggregate metrics ─────────────────────────────────────────────────────────
ARM_A_DATA="{}"
ARM_B_DATA="{}"

if [[ "$ARM" == "A" || "$ARM" == "both" ]]; then
  ARM_A_DATA="$(_aggregate_arm "$RESULTS_A" "true")"
fi
if [[ "$ARM" == "B" || "$ARM" == "both" ]]; then
  ARM_B_DATA="$(_aggregate_arm "$RESULTS_B" "false")"
fi

# ── Delta and gate ───────────────────────────────────────────────────────────
a_ctr="$(printf '%s' "$ARM_A_DATA" | jq -r '.correct_target_rate // 0')"
b_ctr="$(printf '%s' "$ARM_B_DATA" | jq -r '.correct_target_rate // 0')"
a_dr="$(printf '%s' "$ARM_A_DATA" | jq -r '.delegation_rate // 0')"
b_dr="$(printf '%s' "$ARM_B_DATA" | jq -r '.delegation_rate // 0')"

delta_dr="$(jq -n --argjson a "$a_dr" --argjson b "$b_dr" '$a - $b')"
delta_ctr="$(jq -n --argjson a "$a_ctr" --argjson b "$b_ctr" '$a - $b')"

# Gate: arm-A correct_target_rate vs threshold (D-GATE-1: gate on correct_target)
gate_threshold="${MIN:-$DEFAULT_GATE_THRESHOLD}"
a_ctr_pct="$(jq -n --argjson r "$a_ctr" '($r * 100) | floor')"
gate_verdict="PASS"
[[ "$a_ctr_pct" -lt "$gate_threshold" ]] && gate_verdict="FAIL"
reversal_action="advisory default retained"
[[ "$gate_verdict" == "FAIL" ]] && reversal_action="ESCALATE: recommend block default (dossier:106)"

# ── Count sessions run ────────────────────────────────────────────────────────
n_prompts_total="$(printf '%s' "$suite_json" | jq '.tasks | length')"
n_routed_total="$(printf '%s' "$suite_json" | jq '[.tasks[] | select(.control != true and .class != "control")] | length')"
n_control_total="$(printf '%s' "$suite_json" | jq '[.tasks[] | select(.control == true or .class == "control")] | length')"
n_arms_run=0
[[ "$ARM" == "A" || "$ARM" == "both" ]] && n_arms_run=$((n_arms_run + 1))
[[ "$ARM" == "B" || "$ARM" == "both" ]] && n_arms_run=$((n_arms_run + 1))
sessions_run=$(( n_prompts_total * n_arms_run * K ))

scope_note="Non-deterministic (model in loop); k=${K}. k=1 is noise for a headline claim. Tool surface restricted to Task/Read/Grep/Glob — the A−B delta is the harness effect (common-mode bias cancels); absolute arm-A rate is a floor under a read-only surface."

# ── Emit scorecard ───────────────────────────────────────────────────────────
scorecard="$(jq -nc \
  --arg cv "$COMPLIANCE_VERSION" \
  --arg mode "$MODE_LABEL" \
  --arg driver "${DRIVER_CMD:-claude -p --model ${MODEL}}" \
  --arg model "$MODEL" \
  --argjson max_turns "$MAX_TURNS" \
  --argjson k "$K" \
  --arg suite "$SUITE" \
  --argjson n_prompts "$n_prompts_total" \
  --argjson n_routed "$n_routed_total" \
  --argjson n_control "$n_control_total" \
  --argjson sessions_run "$sessions_run" \
  --argjson arm_a "$ARM_A_DATA" \
  --argjson arm_b "$ARM_B_DATA" \
  --argjson delta_dr "$delta_dr" \
  --argjson delta_ctr "$delta_ctr" \
  --argjson gate_val "$a_ctr" \
  --argjson gate_thr "$gate_threshold" \
  --arg gate_verdict "$gate_verdict" \
  --arg reversal_action "$reversal_action" \
  --arg scope_note "$scope_note" \
  '{
    compliance_version: $cv,
    mode: $mode,
    driver: $driver,
    model: $model,
    max_turns: $max_turns,
    k: $k,
    suite: $suite,
    n_prompts: $n_prompts,
    n_routed: $n_routed,
    n_control: $n_control,
    sessions_run: $sessions_run,
    arms: {
      A: $arm_a,
      B: $arm_b
    },
    delta: {
      delegation_rate: $delta_dr,
      correct_target_rate: $delta_ctr
    },
    gate: {
      metric: "A.correct_target_rate",
      value: $gate_val,
      threshold: $gate_thr,
      verdict: $gate_verdict,
      reversal_action: $reversal_action
    },
    scope_note: $scope_note
  }')"

if [[ "$OUT" == "json" ]]; then
  printf '%s\n' "$scorecard"
else
  # Text scorecard (stdout, mirrors eval_swe / eval routing style)
  printf '\n'
  printf '%seidolons eval compliance scorecard%s\n' "${BOLD:-}" "${RESET:-}"
  printf '  mode=%s  driver=%s  k=%s\n' "$MODE_LABEL" "${DRIVER_CMD:-claude -p}" "$K"
  printf '\n'
  printf '  ARM A (harness=ON):\n'
  printf '    delegation_rate:     %s\n' "$(printf '%s' "$ARM_A_DATA" | jq -r '.delegation_rate * 100 | floor / 100')"
  printf '    correct_target_rate: %s\n' "$(printf '%s' "$ARM_A_DATA" | jq -r '.correct_target_rate * 100 | floor / 100')"
  printf '    control_pass_rate:   %s\n' "$(printf '%s' "$ARM_A_DATA" | jq -r '.control_pass_rate * 100 | floor / 100')"
  printf '    stability_passk:     %s\n' "$(printf '%s' "$ARM_A_DATA" | jq -r '.stability_passk * 100 | floor / 100')"
  printf '\n'
  printf '  ARM B (harness=OFF):\n'
  printf '    delegation_rate:     %s\n' "$(printf '%s' "$ARM_B_DATA" | jq -r '.delegation_rate * 100 | floor / 100')"
  printf '    correct_target_rate: %s\n' "$(printf '%s' "$ARM_B_DATA" | jq -r '.correct_target_rate * 100 | floor / 100')"
  printf '    control_pass_rate:   %s\n' "$(printf '%s' "$ARM_B_DATA" | jq -r '.control_pass_rate * 100 | floor / 100')"
  printf '    stability_passk:     %s\n' "$(printf '%s' "$ARM_B_DATA" | jq -r '.stability_passk * 100 | floor / 100')"
  printf '\n'
  printf '  Delta(A-B):\n'
  printf '    delegation_rate:     %s\n' "$(printf '%s' "$delta_dr" | jq -r '. * 100 | floor / 100')"
  printf '    correct_target_rate: %s\n' "$(printf '%s' "$delta_ctr" | jq -r '. * 100 | floor / 100')"
  printf '\n'
  # Per-class breakdown (ARM A)
  if [[ "$ARM" == "A" || "$ARM" == "both" ]]; then
    printf '  ARM A by class:\n'
    printf '%s' "$ARM_A_DATA" | jq -r '.by_class[] | "    \(.class)\tdr=\(.delegation_rate * 100 | floor / 100)\tctr=\(.correct_target_rate * 100 | floor / 100)"'
    printf '\n'
  fi
  printf '  GATE (FORGE reversal, dossier:106): arm-A correct_target_rate = %s%%\n' "$a_ctr_pct"
  printf '    threshold = %s%%  →  %s (%s)\n' "$gate_threshold" "$gate_verdict" "$reversal_action"
  printf '\n'
  printf '  %s⚠ %s%s\n' "${YELLOW:-}" "$scope_note" "${RESET:-}"
fi

# ── Gate exits ────────────────────────────────────────────────────────────────
if [[ "$GATE" == true || -n "$MIN" ]]; then
  if [[ "$gate_verdict" == "FAIL" ]]; then
    [[ "$OUT" != "json" ]] && warn "arm-A correct_target_rate ${a_ctr_pct}% < threshold ${gate_threshold}%  →  FORGE reversal condition triggered"
    exit 1
  fi
fi

exit 0
