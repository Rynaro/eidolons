#!/usr/bin/env bash
# evals/hooks/keep-system.sh — REFERENCE --fix-hook: the "system" arm for H-WIN
# ═══════════════════════════════════════════════════════════════════════════
# H-WIN (the campaign's headline claim): "a light-tier model inside the
# system >= a standard-tier model bare." The HONEST comparison for that claim
# is (light+system) vs (standard+bare) — never bare-vs-system at the SAME
# tier (that would only measure the harness effect, not H-WIN). This hook is
# the "system" reference arm: the SAME task input as keep-bare.sh, but the
# prompt front-loads Kupo's execution discipline (keep-or-kick + patch-verify)
# and the tier-execution dial's light-tier row. Pair it with keep-bare.sh via
# an eval-arms.json (schema: ../../schemas/eval-arms.schema.json), e.g.
# ../arms/h-win.json, and run:
#   eidolons eval swe --matrix evals/arms/h-win.json [--smoke]
#
# Model-agnostic by design: the CALLER sets EIDOLONS_EVAL_MODEL via the arm's
# `env` block in arms.json — this hook never hardcodes a model name/tier.
#
# ⚠️ PROMPTS ARE VERSIONED ARTIFACTS. The wording below (both the discipline
# block and the task framing) is part of what a scorecard measures — changing
# it invalidates any baseline recorded against the previous wording. Bump the
# arm `label` (not just this comment) if you intentionally change the prompt.
#
# Loop contract (cli/src/sandbox.sh, roster/aci.yaml loop_contract): runs in
# the per-attempt task workdir (cwd = the broken repo checkout); 5-minute
# timeout; FAILS OPEN to a non-zero exit — a timed-out or errored call never
# hangs the sandbox loop and never masks the failure as a silent success.

set -euo pipefail

: "${EIDOLONS_EVAL_MODEL:?keep-system.sh: EIDOLONS_EVAL_MODEL is required (set it in the arm env block in arms.json - this hook is model-agnostic and never hardcodes a model)}"

_brief="${EIDOLONS_EVAL_TASK_BRIEF:-}"
if [[ -z "$_brief" ]]; then
  _brief="(no task description supplied — inspect the failing test in this workdir to find the bug.)"
fi

# ── Kupo execution discipline ────────────────────────────────────────────
# Prefer the INSTALLED methodology from the nexus cache (if this project has
# ever synced kupo, its SPEC.md is the source of truth and stays current with
# the shipped methodology). Fall back to a compact static copy — Kupo is
# in_construction (roster/index.yaml) and most eval hosts will not have it
# cached, so the fallback is the common path today.
_kupo_home="${EIDOLONS_HOME:-${HOME:-/root}/.eidolons}"
_kupo_spec=""
for _d in "$_kupo_home"/cache/kupo@*; do
  [[ -f "$_d/SPEC.md" ]] || continue
  _kupo_spec="$_d/SPEC.md"
  break
done

if [[ -n "$_kupo_spec" ]]; then
  # Cap at ~4000 chars so a large SPEC.md cannot blow the prompt budget —
  # the discipline summary, not the full document, is what the prompt needs.
  _discipline="$(head -c 4000 "$_kupo_spec")"
else
  _discipline="$(cat <<'DISC'
Execution discipline (Kupo keep-or-kick + patch-verify — compact static copy;
the installed methodology cache was not found, see roster/index.yaml:kupo):
- KEEP scope only: a bounded, localized change touching AT MOST 2 files.
  Anything wider (cross-cutting, ambiguous, multi-module) is a KICK — refuse
  or escalate rather than guess past your scope.
- Every patch must be checked by a NAMED external verifier (the task's test
  command) before you consider it done. Never declare success without
  running the verifier and observing it pass.
- Propose-only mindset: produce the smallest diff that fixes the failure.
- Test files are READ-ONLY. Do not edit, delete, or weaken the test that
  defines success — that is reward-hacking, not a fix, and is mechanically
  detected (the sandbox loop's test-tamper ratchet rejects it).
- Tier-execution dial, light-tier row: take ONE bounded step at a time,
  prefer targeted search-replace edits over full-file rewrites, and verify
  after EACH step before moving to the next.
DISC
)"
fi

_prompt="$(cat <<EOF
$_discipline

Task:
$_brief

Fix the code so the test passes; do not modify tests.
EOF
)"

# Portable 5-minute timeout: background + SIGKILL, no dependency on GNU
# coreutils' timeout/gtimeout (mirrors cli/src/lib.sh's with_timeout shape,
# trimmed for a standalone reference hook).
_run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "$secs" && kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local timer=$!
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  kill "$timer" 2>/dev/null || true
  wait "$timer" 2>/dev/null || true
  # 137 = SIGKILL, 143 = SIGTERM — either means the timer fired first.
  [[ "$rc" -eq 137 || "$rc" -eq 143 ]] && rc=124
  return "$rc"
}

if ! command -v claude >/dev/null 2>&1; then
  echo "keep-system.sh: 'claude' binary not found on PATH" >&2
  exit 1
fi

# --permission-mode acceptEdits: headless -p cannot Write/Edit without a
# permission grant (verified: a live probe ran the model but left the repo
# untouched). Edits are confined to the ephemeral per-attempt workdir the
# loop creates — the exact scope acceptEdits is safe for.
# Prompt via STDIN, never positional argv: a prompt whose first character is
# '-' (e.g. a methodology excerpt starting with markdown bullets or YAML
# frontmatter '---') is parsed by the CLI as an option and rejected —
# observed live as the system arm scoring 0/12 while echoing its own prompt.
printf '%s' "$_prompt" | _run_with_timeout 300 claude -p --model "$EIDOLONS_EVAL_MODEL" --permission-mode acceptEdits >&2
