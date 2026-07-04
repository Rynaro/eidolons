#!/usr/bin/env bash
# evals/hooks/keep-bare.sh — REFERENCE --fix-hook: the "bare" arm for H-WIN
# ═══════════════════════════════════════════════════════════════════════════
# H-WIN (the campaign's headline claim): "a light-tier model inside the
# system >= a standard-tier model bare." The HONEST comparison for that claim
# is (light+system) vs (standard+bare) — never bare-vs-system at the SAME
# tier (that would only measure the harness effect, not H-WIN). This hook is
# the "bare" reference arm: a minimal prompt, no Kupo execution discipline,
# no scope guard. Pair it with keep-system.sh (the "system" arm) via an
# eval-arms.json (schema: ../../schemas/eval-arms.schema.json), e.g.
# ../arms/h-win.json, and run:
#   eidolons eval swe --matrix evals/arms/h-win.json [--smoke]
#
# Model-agnostic by design: the CALLER sets EIDOLONS_EVAL_MODEL via the arm's
# `env` block in arms.json — this hook never hardcodes a model name/tier.
#
# ⚠️ PROMPTS ARE VERSIONED ARTIFACTS. The wording below is part of what a
# scorecard measures — changing it invalidates any baseline recorded against
# the previous wording. Bump the arm `label` (not just this comment) if you
# intentionally change the prompt, so `eidolons eval baseline` diffs against
# a distinct series instead of silently comparing apples to oranges.
#
# Loop contract (cli/src/sandbox.sh, roster/aci.yaml loop_contract): runs in
# the per-attempt task workdir (cwd = the broken repo checkout); 5-minute
# timeout; FAILS OPEN to a non-zero exit — a timed-out or errored call never
# hangs the sandbox loop and never masks the failure as a silent success. The
# loop treats a non-zero fix-hook exit as "continue and evaluate whatever
# state resulted" (it does not abort the run), matching every other hook in
# this codebase.

set -euo pipefail

: "${EIDOLONS_EVAL_MODEL:?keep-bare.sh: EIDOLONS_EVAL_MODEL is required (set it in the arm env block in arms.json - this hook is model-agnostic and never hardcodes a model)}"

_brief="${EIDOLONS_EVAL_TASK_BRIEF:-}"
if [[ -z "$_brief" ]]; then
  _brief="(no task description supplied — inspect the failing test in this workdir to find the bug.)"
fi

_prompt="$(cat <<EOF
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
  echo "keep-bare.sh: 'claude' binary not found on PATH" >&2
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
