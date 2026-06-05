#!/usr/bin/env bash
# eidolons sandbox — bounded, delegated edit-run-test loop harness (roadmap #9)
# ═══════════════════════════════════════════════════════════════════════════
# Closes the largest competitive gap (the OpenHands/Cursor/Devin closed loop) —
# but as an ADAPTER, never an engine. The nexus has NO LLM and NEVER builds a
# sandbox (the dossier's clearest build-vs-buy anti-recommendation). It supplies:
#   - the bounded control flow + the ≤N-attempt hard cap (Prime Directive D5,
#     made executable),
#   - diff-not-apply discipline (emits a candidate diff for review; NEVER commits
#     or merges),
#   - a mandatory VIGIL hand-off on cap-out (never a silent retry),
#   - STRUCTURED LOCALIZED FEEDBACK + anti-reward-hacking gates + pass^k, per the
#     loop_contract in roster/aci.yaml (added 2026-06 for the APIVR-Δ → Vivi
#     succession; see DOSSIER-APIVR-OVERHAUL-2026-06.md). Localized feedback (the
#     failing markers + file:line loci + the FULL log) replaces the un-localized
#     `tail -n 20` — a model fixes an error when told WHERE it is (Tyen et al.).
# It DELEGATES:
#   - isolation to a host/user-provided sandbox via `--via <cmd>` (microVM/gVisor/
#     container) and REFUSES to run untrusted/LLM-authored code on the bare host
#     unless `--allow-unsafe-host` is given (R8-03: LLM code needs hardware-level
#     isolation),
#   - the edit/LLM step to a host-provided `--fix-hook <cmd>` (that is where the
#     model lives — e.g. a Vivi invocation; APIVR-Δ is the non-loop fallback).
#
#   eidolons sandbox check [--via <cmd>] [--allow-unsafe-host]
#   eidolons sandbox run   [--via <cmd>] [--allow-unsafe-host] -- <test-cmd...>
#   eidolons sandbox loop  --tests <cmd> [--fix-hook <cmd>] [--via <cmd>]
#                          [--max-attempts N] [--base <ref>] [--out <dir>]
#                          [--protect <glob>] [--regression <cmd>]
#                          [--reproduction <cmd>] [--k N] [--allow-unsafe-host]
#
# Opt-in by design (agentic loops cost up to ~50x). Tokens/cost are the host's.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<EOF
eidolons sandbox — bounded, delegated edit-run-test loop (adapter, not an engine)

Usage:
  eidolons sandbox check [--via <cmd>] [--allow-unsafe-host] [--json]
  eidolons sandbox run   [--via <cmd>] [--allow-unsafe-host] [--json] -- <test-cmd...>
  eidolons sandbox loop  --tests <test-cmd> [--fix-hook <cmd>] [--via <cmd>]
                         [--max-attempts N] [--base <ref>] [--out <dir>]
                         [--protect <glob>] [--regression <cmd>] [--reproduction <cmd>]
                         [--k N] [--allow-unsafe-host] [--json]

check   Classify the isolation tier of --via and apply the refusal policy
        (untrusted code needs >= container isolation).
run     Run a test command through the delegated sandbox; capture pass/fail.
loop    Bounded edit-run-test loop: run tests -> on fail call --fix-hook (the
        host's LLM/edit step) -> retry, capped at --max-attempts (default 3).
        Emits a candidate diff for review (NEVER commits/merges). On cap-out,
        emits a mandatory VIGIL repair-failed-report and exits 3.

        loop_contract (roster/aci.yaml) extras:
          --protect <glob>      anchoring tests the fix-hook MUST NOT edit; a
                                mutation aborts the loop + escalates (anti-cheat).
          --regression <cmd>    run FIRST; --reproduction <cmd> runs only if it
          --reproduction <cmd>  passes (regression-first; passing only the new
                                test FAILS).
          --k N                 pass^k: a green candidate must pass N re-runs in a
                                row; a non-deterministic pass is flaky -> BLOCKED.
        The fix-hook receives EIDOLONS_SANDBOX_FEEDBACK (structured JSON: failing
        markers, file:line loci, full-log path) — localized, not a raw tail.

The nexus DELEGATES isolation (--via) and the edit step (--fix-hook); it owns only
the bounded control flow, diff-not-apply discipline, the anti-reward-hacking gates,
and the VIGIL escalation.
EOF
}

# ── isolation tier inference from the --via wrapper ───────────────────────────
_isolation_tier() {
  local via="$1"
  [[ -z "$via" ]] && { echo "none"; return; }
  case "$via" in
    *firecracker*|*gvisor*|*microvm*|*e2b*|*kata*|*runsc*) echo "microvm" ;;
    *docker*|*podman*|*nerdctl*|*container*|*lxc*|*bwrap*|*bubblewrap*) echo "container" ;;
    *) echo "delegated" ;;  # user-provided wrapper we cannot classify — trust it
  esac
}
_adequate_for_untrusted() { case "$1" in microvm|container|delegated) return 0 ;; *) return 1 ;; esac; }

SUB="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$SUB" in
  -h|--help|"") usage; exit 0 ;;
  check|run|loop) ;;
  *) die "Unknown subcommand: $SUB (want: check | run | loop). See 'eidolons sandbox --help'" ;;
esac

VIA=""
ALLOW_UNSAFE=false
OUT="text"
TESTS=""
FIX_HOOK=""
MAX_ATTEMPTS=3
BASE="HEAD"
OUT_DIR=""
PROTECT=""
REGRESSION=""
REPRODUCTION=""
K=1
TEST_CMD=()
_after_dd=false
while [[ $# -gt 0 ]]; do
  if [[ "$_after_dd" == true ]]; then TEST_CMD+=("$1"); shift; continue; fi
  case "$1" in
    --via)               VIA="${2:-}"; shift 2 ;;
    --allow-unsafe-host) ALLOW_UNSAFE=true; shift ;;
    --json)              OUT="json"; shift ;;
    --tests)             TESTS="${2:-}"; shift 2 ;;
    --fix-hook)          FIX_HOOK="${2:-}"; shift 2 ;;
    --max-attempts)      MAX_ATTEMPTS="${2:-3}"; shift 2 ;;
    --base)              BASE="${2:-HEAD}"; shift 2 ;;
    --out)               OUT_DIR="${2:-}"; shift 2 ;;
    --protect)           PROTECT="${PROTECT:+$PROTECT }${2:-}"; shift 2 ;;
    --regression)        REGRESSION="${2:-}"; shift 2 ;;
    --reproduction)      REPRODUCTION="${2:-}"; shift 2 ;;
    --k)                 K="${2:-1}"; shift 2 ;;
    --)                  _after_dd=true; shift ;;
    -h|--help)           usage; exit 0 ;;
    -*)                  die "Unknown option: $1" ;;
    *)                   TEST_CMD+=("$1"); shift ;;
  esac
done

TIER="$(_isolation_tier "$VIA")"

# ── Shared isolation gate: refuse untrusted execution without isolation ───────
_assert_isolation() {
  if _adequate_for_untrusted "$TIER"; then return 0; fi
  if [[ "$ALLOW_UNSAFE" == true ]]; then
    # Suppress progress chatter in --json mode so machine output stays clean.
    [[ "$OUT" != "json" ]] && warn "sandbox: running on the BARE HOST with no isolation (--allow-unsafe-host). Only do this for code you trust."
    return 0
  fi
  die "sandbox: no adequate isolation (tier=$TIER). LLM-authored/untrusted code needs >= container isolation. Pass --via '<sandbox-cmd>' (e.g. docker/gvisor/firecracker/e2b) or, for trusted code only, --allow-unsafe-host."
}

# ── Run a command through the delegated sandbox; echo result JSON ──────────────
# Args (both optional):
#   $1 cmd_str  — a command STRING to run via bash -c (regression/reproduction
#                 phases). If empty, run the TEST_CMD array (the `run` subcommand
#                 and the default loop --tests path) for back-compat.
#   $2 logdest  — a stable path for the FULL log; if empty, a temp log is used and
#                 reaped (and .full_log is "").
# Result JSON: {passed, exit_code, duration_s, output_tail, full_log, failing, loci}
# `failing`/`loci` are a BEST-EFFORT localized extraction (loop_contract); the
# coder does the deep parse. The full log is preserved (never only a tail).
_run_in_sandbox() {
  local cmd_str="${1:-}" logdest="${2:-}"
  local logf rc=0 start end keep=true
  if [[ -n "$logdest" ]]; then logf="$logdest"; else logf="$(mktemp)"; keep=false; fi
  start="$(date +%s)"
  # `|| rc=$?` captures the test's REAL exit code (a plain `|| true` would mask it)
  # AND keeps `set -e` from exiting on a failing test.
  if [[ -n "$cmd_str" ]]; then
    if [[ -n "$VIA" ]]; then
      # shellcheck disable=SC2086
      eval "$VIA" "$cmd_str" >"$logf" 2>&1 || rc=$?
    else
      bash -c "$cmd_str" >"$logf" 2>&1 || rc=$?
    fi
  elif [[ -n "$VIA" ]]; then
    # shellcheck disable=SC2086
    eval "$VIA" "${TEST_CMD[@]+"${TEST_CMD[@]}"}" >"$logf" 2>&1 || rc=$?
  else
    "${TEST_CMD[@]}" >"$logf" 2>&1 || rc=$?
  fi
  end="$(date +%s)"
  local tail_txt failing loci full_ref
  tail_txt="$(tail -n 40 "$logf" 2>/dev/null || true)"
  failing="$(grep -nEi '(fail(ed|ure)?|error|exception|assert|panic:|not ok|--- FAIL|FAILED|traceback)' "$logf" 2>/dev/null | head -n 30 || true)"
  # Deepened loci extraction: three formats handled.
  # Format 1 (colon form): file.ext:NN — pytest, go test, generic
  # Format 2 (bats): "(in test file <name>, line NN)"
  # Format 3 (shellcheck): "In <file> line NN:"
  loci_colon="$(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' "$logf" 2>/dev/null || true)"
  loci_bats="$(grep -oE 'in test file [A-Za-z0-9_./-]+,? line [0-9]+' "$logf" 2>/dev/null \
    | sed 's/in test file \([^ ,]*\),\? line \([0-9]*\)/\1:\2/' || true)"
  loci_sc="$(grep -oE 'In [A-Za-z0-9_./-]+ line [0-9]+:' "$logf" 2>/dev/null \
    | sed 's/In \([^ ]*\) line \([0-9]*\):/\1:\2/' || true)"
  loci="$(printf '%s\n%s\n%s\n' "$loci_colon" "$loci_bats" "$loci_sc" \
    | grep -v '^$' | sort -u | head -n 20 || true)"
  # Failing test names: "not ok N <name>" (bats) and "FAILED <module>::<name>" (pytest).
  test_names_bats="$(grep -oE 'not ok [0-9]+ .+' "$logf" 2>/dev/null \
    | sed 's/not ok [0-9]* //' || true)"
  test_names_pytest="$(grep -oE 'FAILED [A-Za-z0-9_./-]+::[A-Za-z0-9_]+' "$logf" 2>/dev/null \
    | sed 's/FAILED //' || true)"
  test_name="$(printf '%s\n%s\n' "$test_names_bats" "$test_names_pytest" \
    | grep -v '^$' | head -n 5 || true)"
  # Assertion extraction: "assert X == Y" (pytest E-line), `[ "$x" -eq Y ]' failed (bats).
  assertion="$(grep -E '^E\s+(assert|AssertionError)' "$logf" 2>/dev/null | head -n 5 \
    || grep -oE "\`[^']+' failed" "$logf" 2>/dev/null | head -n 5 || true)"
  if [[ "$keep" == true ]]; then full_ref="$logf"; else full_ref=""; fi
  jq -nc --argjson rc "$rc" --argjson dur "$((end - start))" \
    --arg tail "$tail_txt" --arg full "$full_ref" --arg failing "$failing" --arg loci "$loci" \
    --arg test_name "$test_name" --arg assertion "$assertion" \
    '{passed: ($rc == 0), exit_code: $rc, duration_s: $dur, output_tail: $tail,
      full_log: $full, failing: $failing, loci: ($loci | split("\n") | map(select(length>0))),
      test_name: ($test_name | split("\n") | map(select(length>0))),
      assertion: ($assertion | split("\n") | map(select(length>0)))}'
  [[ "$keep" == false ]] && rm -f "$logf"
  return 0
}

# ── One loop iteration's success check: regression-first then reproduction, or a
# single --tests run. Echoes the result JSON with a `phase` tag. ───────────────
_eval_once() {
  local logdest="$1" reg repro
  if [[ -n "$REGRESSION" || -n "$REPRODUCTION" ]]; then
    if [[ -n "$REGRESSION" ]]; then
      reg="$(_run_in_sandbox "$REGRESSION" "$logdest")"
      if [[ "$(printf '%s' "$reg" | jq -r '.passed')" != "true" ]]; then
        printf '%s' "$reg" | jq -c '. + {phase:"regression"}'; return 0
      fi
    fi
    if [[ -n "$REPRODUCTION" ]]; then
      repro="$(_run_in_sandbox "$REPRODUCTION" "$logdest")"
      printf '%s' "$repro" | jq -c '. + {phase:"reproduction"}'; return 0
    fi
    printf '%s' "$reg" | jq -c '. + {phase:"regression"}'; return 0
  fi
  _run_in_sandbox "" "$logdest" | jq -c '. + {phase:"tests"}'
  return 0
}

# ── Anti-reward-hacking: a single signature over the protected (anchoring) test
# files. A change between baseline and post-fix-hook = evaluator-gaming. ────────
_protect_snapshot() {
  [[ -z "$PROTECT" ]] && { printf ''; return 0; }
  local g f acc=""
  for g in $PROTECT; do          # intentional word-split: globs are space-separated
    # shellcheck disable=SC2231
    for f in $g; do              # intentional glob expansion (literal if no match)
      [[ -f "$f" ]] && acc="$acc$(cksum "$f" 2>/dev/null) "
    done
  done
  printf '%s' "$acc" | cksum | awk '{print $1"-"$2}'
  return 0
}

case "$SUB" in
  # ── check: isolation preflight + refusal policy ─────────────────────────────
  check)
    adequate=false; _adequate_for_untrusted "$TIER" && adequate=true
    verdict="ok"; reason="isolation adequate for untrusted code (tier=$TIER)"
    if [[ "$adequate" != true ]]; then
      if [[ "$ALLOW_UNSAFE" == true ]]; then verdict="unsafe-host-override"; reason="no isolation; proceeding on bare host by --allow-unsafe-host (trusted code only)"
      else verdict="refuse"; reason="no adequate isolation; supply --via <sandbox-cmd> or --allow-unsafe-host"; fi
    fi
    if [[ "$OUT" == "json" ]]; then
      jq -nc --arg via "$VIA" --arg tier "$TIER" --argjson adequate "$adequate" \
        --argjson unsafe "$ALLOW_UNSAFE" --arg verdict "$verdict" --arg reason "$reason" \
        '{via:$via, tier:$tier, adequate_for_untrusted:$adequate, allow_unsafe_host:$unsafe, verdict:$verdict, reason:$reason}'
    else
      printf '%ssandbox isolation%s  tier=%s  adequate=%s  →  %s\n' "${BOLD:-}" "${RESET:-}" "$TIER" "$adequate" "$verdict"
      printf '  %s\n' "$reason"
    fi
    [[ "$verdict" == "refuse" ]] && exit 3
    exit 0
    ;;

  # ── run: a single sandboxed test run ────────────────────────────────────────
  run)
    [[ ${#TEST_CMD[@]} -gt 0 ]] || die "run needs a test command after '--' (e.g. eidolons sandbox run --via 'docker run ...' -- pytest)"
    _assert_isolation
    result="$(_run_in_sandbox)"
    if [[ "$OUT" == "json" ]]; then printf '%s\n' "$result"
    else
      passed="$(printf '%s' "$result" | jq -r '.passed')"
      printf '%ssandbox run%s  tier=%s  passed=%s  (%ss)\n' "${BOLD:-}" "${RESET:-}" "$TIER" "$passed" "$(printf '%s' "$result" | jq -r '.duration_s')"
    fi
    [[ "$(printf '%s' "$result" | jq -r '.passed')" == "true" ]] && exit 0 || exit 1
    ;;

  # ── loop: bounded edit-run-test; diff-not-apply; VIGIL on cap-out ───────────
  loop)
    [[ -n "$TESTS" || -n "$REGRESSION" || -n "$REPRODUCTION" ]] || die "loop needs --tests <test-cmd> (or --regression/--reproduction)"
    if [[ -n "$TESTS" ]]; then
      # shellcheck disable=SC2206
      TEST_CMD=($TESTS)   # word-split the test command for execution
    fi
    _assert_isolation
    [[ "$MAX_ATTEMPTS" -ge 1 ]] 2>/dev/null || die "--max-attempts must be >= 1"
    [[ "$K" -ge 1 ]] 2>/dev/null || die "--k must be >= 1"

    # Output dir (diff-not-apply artifacts + VIGIL hand-off live here).
    if [[ -z "$OUT_DIR" ]]; then OUT_DIR=".eidolons/sandbox/run-$(date +%Y%m%d-%H%M%S)"; fi
    mkdir -p "$OUT_DIR"

    have_git=false
    if git rev-parse --git-dir >/dev/null 2>&1; then have_git=true; fi
    base_sha=""
    [[ "$have_git" == true ]] && base_sha="$(git rev-parse "$BASE" 2>/dev/null || echo "")"

    # Anti-reward-hacking: baseline signature of the protected anchoring tests.
    protect_baseline="$(_protect_snapshot)"

    attempts="[]"
    final="capped"
    last_flaky=false
    n=0
    while [[ "$n" -lt "$MAX_ATTEMPTS" ]]; do
      n=$((n + 1))
      last_flaky=false
      result="$(_eval_once "$OUT_DIR/full-log.txt")"
      passed="$(printf '%s' "$result" | jq -r '.passed')"

      # pass^k: a green that is non-deterministic across k re-runs is flaky → BLOCKED.
      # per-k breakdown: record each re-run result for the passk ledger field.
      passk_runs="[]"
      if [[ "$passed" == "true" && "$K" -gt 1 ]]; then
        passk_runs="$(printf '%s' "$passk_runs" | jq -c \
          --argjson r "$result" --argjson ki 1 \
          '. + [{run:$ki, passed:$r.passed, exit_code:$r.exit_code}]')"
        kk=1; flaky=false
        while [[ "$kk" -lt "$K" ]]; do
          kk=$((kk + 1))
          r2="$(_eval_once "$OUT_DIR/full-log.txt")"
          r2_passed="$(printf '%s' "$r2" | jq -r '.passed')"
          r2_rc="$(printf '%s' "$r2" | jq -r '.exit_code')"
          passk_runs="$(printf '%s' "$passk_runs" | jq -c \
            --argjson ki "$kk" --argjson rp "$([ "$r2_passed" = "true" ] && printf 'true' || printf 'false')" \
            --argjson rc2 "${r2_rc:-1}" \
            '. + [{run:$ki, passed:$rp, exit_code:$rc2}]')"
          if [[ "$r2_passed" != "true" ]]; then flaky=true; break; fi
        done
        if [[ "$flaky" == true ]]; then
          passed="false"; last_flaky=true
          result="$(printf '%s' "$result" | jq -c --argjson k "$K" '. + {passed:false, flaky:true, k:$k}')"
          [[ "$OUT" != "json" ]] && warn "sandbox loop: attempt $n passed once but is FLAKY across k=$K — BLOCKED (not accepted)"
        fi
      else
        # K=1: single run; still record for the breakdown
        _r1_passed_val="$(printf '%s' "$result" | jq -r '.passed')"
        _r1_rc_val="$(printf '%s' "$result" | jq -r '.exit_code')"
        passk_runs="$(printf '%s' "$passk_runs" | jq -c \
          --argjson ki 1 \
          --argjson rp "$([ "$_r1_passed_val" = "true" ] && printf 'true' || printf 'false')" \
          --argjson rc1 "${_r1_rc_val:-1}" \
          '. + [{run:$ki, passed:$rp, exit_code:$rc1}]')"
      fi

      # Structured localized feedback artefact (loop_contract) — replaces tail -n 20.
      printf '%s' "$result" | jq -r '.output_tail' > "$OUT_DIR/last-output.txt"
      printf '%s' "$result" | jq -c --argjson n "$n" \
        '{contract_version:"1.0", attempt:$n, exit_code:.exit_code, phase:.phase, passed:.passed,
          flaky:(.flaky // false), failing:.failing, loci:.loci,
          test_name:(.test_name // []), assertion:(.assertion // []),
          full_log:"full-log.txt", output_tail:.output_tail}' > "$OUT_DIR/feedback.json"

      attempts="$(printf '%s' "$attempts" | jq --argjson n "$n" --argjson r "$result" \
        --argjson pkruns "$passk_runs" \
        '. + [{attempt:$n, passed:$r.passed, exit_code:$r.exit_code, duration_s:($r.duration_s // 0), phase:($r.phase // "tests"), flaky:($r.flaky // false), passk_runs:$pkruns}]')"

      if [[ "$passed" == "true" ]]; then final="passed"; break; fi
      [[ "$n" -ge "$MAX_ATTEMPTS" ]] && break
      if [[ -z "$FIX_HOOK" ]]; then
        # No edit source — a loop with no fix-hook degrades to a single verify.
        final="no_fix_hook"; break
      fi
      # DELEGATE the edit/LLM step to the host. The fix-hook edits the working
      # tree; the nexus NEVER edits or merges. Localized context passed via env.
      [[ "$OUT" != "json" ]] && warn "sandbox loop: attempt $n failed — invoking --fix-hook (host edit step)"
      _fh_rc=0
      EIDOLONS_SANDBOX_FEEDBACK="$OUT_DIR/feedback.json" \
      EIDOLONS_SANDBOX_FULL_LOG="$OUT_DIR/full-log.txt" \
      EIDOLONS_SANDBOX_LAST_OUTPUT="$OUT_DIR/last-output.txt" \
      EIDOLONS_SANDBOX_ATTEMPT="$n" \
      EIDOLONS_SANDBOX_BASE="$base_sha" \
        bash -c "$FIX_HOOK" >&2 || _fh_rc=$?
      # `>&2`: the fix-hook communicates by EDITING the working tree; its stdout is
      # diagnostic only (LLM CLIs print verbose responses). Route it to stderr so a
      # chatty fix-hook can NEVER corrupt the loop's own `--json` ledger on stdout.
      [[ "$_fh_rc" -ne 0 && "$OUT" != "json" ]] && warn "sandbox loop: --fix-hook returned $_fh_rc (continuing to re-test)"

      # Anti-reward-hacking gate: did the fix-hook mutate a protected test file?
      if [[ -n "$PROTECT" ]]; then
        if [[ "$(_protect_snapshot)" != "$protect_baseline" ]]; then
          final="protected-tests-mutated"
          [[ "$OUT" != "json" ]] && warn "sandbox loop: --fix-hook MUTATED a protected anchoring test (--protect) — ABORT + escalate (anti-reward-hacking)"
          break
        fi
      fi
    done

    # A capped loop whose last attempt was a blocked flaky green reports `flaky`.
    [[ "$final" == "capped" && "$last_flaky" == "true" ]] && final="flaky"

    # Candidate diff (diff-not-apply): emit, never commit/merge.
    diff_path=""
    if [[ "$have_git" == true ]]; then
      diff_path="$OUT_DIR/candidate.diff"
      git diff "${base_sha:-$BASE}" > "$diff_path" 2>/dev/null || git diff > "$diff_path" 2>/dev/null || true
    fi

    # VIGIL hand-off on cap-out / flaky / anti-cheat abort (mandatory; never a silent retry).
    vigil_handoff=""
    if [[ "$final" != "passed" ]]; then
      vigil_handoff="$OUT_DIR/repair-failed-report.md"
      _reason="bounded retry budget exhausted on the same category"
      case "$final" in
        flaky)                    _reason="a candidate passed once but is FLAKY across pass^k (k=$K) — BLOCKED, not merged" ;;
        protected-tests-mutated)  _reason="the --fix-hook MUTATED a protected anchoring test (evaluator-gaming) — ABORTED" ;;
        no_fix_hook)              _reason="no --fix-hook supplied; the loop degraded to a single verify" ;;
      esac
      {
        echo "# repair-failed-report → VIGIL (forensic-then-fix)"
        echo ""
        echo "- outcome: $final"
        echo "- reason: $_reason"
        echo "- attempts: $n / $MAX_ATTEMPTS"
        echo "- pass^k: k=$K"
        echo "- tests: \`${TESTS:-${REGRESSION:+regression: $REGRESSION }${REPRODUCTION:+reproduction: $REPRODUCTION}}\`"
        echo "- protected (anchoring) tests: \`${PROTECT:-<none>}\`"
        echo "- isolation tier: $TIER"
        echo "- base: ${base_sha:-$BASE}"
        echo "- candidate diff: ${diff_path:-<none — not a git repo>} (NOT applied/merged)"
        echo "- structured feedback: $OUT_DIR/feedback.json (loop_contract)"
        echo ""
        echo "## last test output (localized; full log: $OUT_DIR/full-log.txt)"
        echo '```'
        cat "$OUT_DIR/last-output.txt" 2>/dev/null || true
        echo '```'
        echo ""
        echo "→ Hand off to VIGIL: reproduction-gated, counterfactual-verified root-cause attribution."
        echo "  The coder exhausted its bounded budget; $_reason."
      } > "$vigil_handoff"
    fi

    # passk summary: k value + all per-attempt runs (additive; .k field preserved for back-compat)
    passk_summary="$(printf '%s' "$attempts" | jq -c \
      --argjson k "$K" \
      '{k:$k, runs:[.[] | {attempt:.attempt, passk_runs:.passk_runs}]}')"
    ledger="$(jq -nc \
      --arg final "$final" --argjson attempts "$attempts" --argjson max "$MAX_ATTEMPTS" \
      --argjson k "$K" --arg protect "$PROTECT" \
      --arg tier "$TIER" --arg base "${base_sha:-$BASE}" --arg diff "$diff_path" \
      --arg feedback "$OUT_DIR/feedback.json" \
      --arg vigil "$vigil_handoff" --arg out "$OUT_DIR" \
      --argjson passk "$passk_summary" \
      '{final:$final, attempts_run:($attempts|length), max_attempts:$max, k:$k,
        protect:$protect, tier:$tier, base:$base, candidate_diff:$diff,
        feedback:$feedback, vigil_handoff:$vigil, out_dir:$out,
        merged:false, attempts:$attempts, passk:$passk}')"
    printf '%s\n' "$ledger" > "$OUT_DIR/loop.json"

    # ECL sidecar: loop.json.envelope.json — inform performative, cksum integrity.
    # Reuses the closed-10 `inform` performative (GAP-2 decision); bash 3.2 safe (cksum).
    # sender="eidolons-sandbox" (stateless substrate identity); receiver="" (consuming agent,
    # Vivi, unknown at substrate level — R1 residual confirmed: empty string is the safe default).
    _loop_cksum="$(cksum "$OUT_DIR/loop.json" 2>/dev/null | awk '{print $1"-"$2}' || echo "0-0")"
    _loop_size="$(cksum "$OUT_DIR/loop.json" 2>/dev/null | awk '{print $2}' || echo "0")"
    _loop_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')"
    jq -nc \
      --arg ts "$_loop_ts" \
      --arg cksum "$_loop_cksum" \
      --argjson sz "$_loop_size" \
      --arg out "$OUT_DIR" \
      '{envelope_version:"1.0",
        performative:"inform",
        sender:{eidolon:"eidolons-sandbox",version:"1.0"},
        receiver:{eidolon:"",version:""},
        artifact:{kind:"loop-ledger",path:"loop.json"},
        integrity:{method:"cksum",value:$cksum,size_bytes:$sz},
        trace:{ts:$ts,out_dir:$out}}' > "$OUT_DIR/loop.json.envelope.json"

    if [[ "$OUT" == "json" ]]; then printf '%s\n' "$ledger"
    else
      printf '%ssandbox loop%s  %s  (%s/%s attempts, k=%s, tier=%s)\n' "${BOLD:-}" "${RESET:-}" "$final" "$n" "$MAX_ATTEMPTS" "$K" "$TIER"
      printf '%s' "$attempts" | jq -r '.[] | "  attempt \(.attempt): \(if .passed then "PASS" else "FAIL" end)\(if .flaky then " (FLAKY)" else "" end) [\(.phase)] (\(.duration_s)s)"'
      [[ -n "$diff_path" ]] && printf '  candidate diff (NOT applied): %s\n' "$diff_path"
      if [[ "$final" == "passed" ]]; then ok "tests pass — review the candidate diff and apply it yourself (diff-not-apply)"
      else warn "cap reached — VIGIL hand-off written: $vigil_handoff"; fi
    fi
    [[ "$final" == "passed" ]] && exit 0 || exit 3
    ;;
esac
