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
#   - a mandatory VIGIL hand-off on cap-out (never a silent retry).
# It DELEGATES:
#   - isolation to a host/user-provided sandbox via `--via <cmd>` (microVM/gVisor/
#     container) and REFUSES to run untrusted/LLM-authored code on the bare host
#     unless `--allow-unsafe-host` is given (R8-03: LLM code needs hardware-level
#     isolation),
#   - the edit/LLM step to a host-provided `--fix-hook <cmd>` (that is where the
#     model lives — e.g. an APIVR-Δ invocation).
#
#   eidolons sandbox check [--via <cmd>] [--allow-unsafe-host]
#   eidolons sandbox run   [--via <cmd>] [--allow-unsafe-host] -- <test-cmd...>
#   eidolons sandbox loop  --tests <cmd> [--fix-hook <cmd>] [--via <cmd>]
#                          [--max-attempts N] [--base <ref>] [--out <dir>]
#                          [--allow-unsafe-host]
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
                         [--allow-unsafe-host] [--json]

check   Classify the isolation tier of --via and apply the refusal policy
        (untrusted code needs >= container isolation).
run     Run a test command through the delegated sandbox; capture pass/fail.
loop    Bounded edit-run-test loop: run tests -> on fail call --fix-hook (the
        host's LLM/edit step) -> retry, capped at --max-attempts (default 3).
        Emits a candidate diff for review (NEVER commits/merges). On cap-out,
        emits a mandatory VIGIL repair-failed-report and exits 3.

The nexus DELEGATES isolation (--via) and the edit step (--fix-hook); it owns only
the bounded control flow, diff-not-apply discipline, and the VIGIL escalation.
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

# ── Run a test command through the delegated sandbox; echo result JSON ────────
# Result: {passed, exit_code, duration_s, output_tail}
_run_in_sandbox() {
  local logf; logf="$(mktemp)"
  local start end rc=0
  start="$(date +%s)"
  # `|| rc=$?` captures the test's REAL exit code (a plain `|| true` would mask it)
  # AND keeps `set -e` from exiting on a failing test.
  if [[ -n "$VIA" ]]; then
    # shellcheck disable=SC2086
    eval "$VIA" "${TEST_CMD[@]+"${TEST_CMD[@]}"}" >"$logf" 2>&1 || rc=$?
  else
    "${TEST_CMD[@]}" >"$logf" 2>&1 || rc=$?
  fi
  end="$(date +%s)"
  local tail_txt; tail_txt="$(tail -n 20 "$logf" 2>/dev/null || true)"
  jq -nc --argjson rc "$rc" --argjson dur "$((end - start))" --arg tail "$tail_txt" \
    '{passed: ($rc == 0), exit_code: $rc, duration_s: $dur, output_tail: $tail}'
  rm -f "$logf"
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
    [[ -n "$TESTS" ]] || die "loop needs --tests <test-cmd>"
    # shellcheck disable=SC2206
    TEST_CMD=($TESTS)   # word-split the test command for execution
    _assert_isolation
    [[ "$MAX_ATTEMPTS" -ge 1 ]] 2>/dev/null || die "--max-attempts must be >= 1"

    # Output dir (diff-not-apply artifacts + VIGIL hand-off live here).
    if [[ -z "$OUT_DIR" ]]; then OUT_DIR=".eidolons/sandbox/run-$(date +%Y%m%d-%H%M%S)"; fi
    mkdir -p "$OUT_DIR"

    have_git=false
    if git rev-parse --git-dir >/dev/null 2>&1; then have_git=true; fi
    base_sha=""
    [[ "$have_git" == true ]] && base_sha="$(git rev-parse "$BASE" 2>/dev/null || echo "")"

    attempts="[]"
    final="capped"
    n=0
    while [[ "$n" -lt "$MAX_ATTEMPTS" ]]; do
      n=$((n + 1))
      result="$(_run_in_sandbox)"
      passed="$(printf '%s' "$result" | jq -r '.passed')"
      # last test output → file the fix-hook can read
      printf '%s' "$result" | jq -r '.output_tail' > "$OUT_DIR/last-output.txt"
      attempts="$(printf '%s' "$attempts" | jq --argjson n "$n" --argjson r "$result" '. + [{attempt:$n} + $r]')"
      if [[ "$passed" == "true" ]]; then final="passed"; break; fi
      [[ "$n" -ge "$MAX_ATTEMPTS" ]] && break
      if [[ -z "$FIX_HOOK" ]]; then
        # No edit source — a loop with no fix-hook degrades to a single verify.
        final="no_fix_hook"; break
      fi
      # DELEGATE the edit/LLM step to the host. The fix-hook edits the working
      # tree; the nexus NEVER edits or merges. Context passed via env.
      [[ "$OUT" != "json" ]] && warn "sandbox loop: attempt $n failed — invoking --fix-hook (host edit step)"
      _fh_rc=0
      EIDOLONS_SANDBOX_LAST_OUTPUT="$OUT_DIR/last-output.txt" \
      EIDOLONS_SANDBOX_ATTEMPT="$n" \
      EIDOLONS_SANDBOX_BASE="$base_sha" \
        bash -c "$FIX_HOOK" || _fh_rc=$?
      [[ "$_fh_rc" -ne 0 && "$OUT" != "json" ]] && warn "sandbox loop: --fix-hook returned $_fh_rc (continuing to re-test)"
    done

    # Candidate diff (diff-not-apply): emit, never commit/merge.
    diff_path=""
    if [[ "$have_git" == true ]]; then
      diff_path="$OUT_DIR/candidate.diff"
      git diff "${base_sha:-$BASE}" > "$diff_path" 2>/dev/null || git diff > "$diff_path" 2>/dev/null || true
    fi

    # VIGIL hand-off on cap-out (mandatory; never a silent retry).
    vigil_handoff=""
    if [[ "$final" != "passed" ]]; then
      vigil_handoff="$OUT_DIR/repair-failed-report.md"
      {
        echo "# repair-failed-report → VIGIL (forensic-then-fix)"
        echo ""
        echo "- outcome: $final"
        echo "- attempts: $n / $MAX_ATTEMPTS (cap reached)"
        echo "- tests: \`$TESTS\`"
        echo "- isolation tier: $TIER"
        echo "- base: ${base_sha:-$BASE}"
        echo "- candidate diff: ${diff_path:-<none — not a git repo>} (NOT applied/merged)"
        echo ""
        echo "## last test output"
        echo '```'
        cat "$OUT_DIR/last-output.txt" 2>/dev/null || true
        echo '```'
        echo ""
        echo "→ Hand off to VIGIL: reproduction-gated, counterfactual-verified root-cause attribution."
        echo "  APIVR-Δ exhausted its bounded retry budget ($MAX_ATTEMPTS) on the same category."
      } > "$vigil_handoff"
    fi

    ledger="$(jq -nc \
      --arg final "$final" --argjson attempts "$attempts" --argjson max "$MAX_ATTEMPTS" \
      --arg tier "$TIER" --arg base "${base_sha:-$BASE}" --arg diff "$diff_path" \
      --arg vigil "$vigil_handoff" --arg out "$OUT_DIR" \
      '{final:$final, attempts_run:($attempts|length), max_attempts:$max, tier:$tier,
        base:$base, candidate_diff:$diff, vigil_handoff:$vigil, out_dir:$out,
        merged:false, attempts:$attempts}')"
    printf '%s\n' "$ledger" > "$OUT_DIR/loop.json"

    if [[ "$OUT" == "json" ]]; then printf '%s\n' "$ledger"
    else
      printf '%ssandbox loop%s  %s  (%s/%s attempts, tier=%s)\n' "${BOLD:-}" "${RESET:-}" "$final" "$n" "$MAX_ATTEMPTS" "$TIER"
      printf '%s' "$attempts" | jq -r '.[] | "  attempt \(.attempt): \(if .passed then "PASS" else "FAIL" end) (\(.duration_s)s)"'
      [[ -n "$diff_path" ]] && printf '  candidate diff (NOT applied): %s\n' "$diff_path"
      if [[ "$final" == "passed" ]]; then ok "tests pass — review the candidate diff and apply it yourself (diff-not-apply)"
      else warn "cap reached — VIGIL hand-off written: $vigil_handoff"; fi
    fi
    [[ "$final" == "passed" ]] && exit 0 || exit 3
    ;;
esac
