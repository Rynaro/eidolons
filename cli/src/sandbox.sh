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
# shellcheck disable=SC1091
. "$SELF_DIR/lib_patch_applier.sh"
# Absolute path to THIS script, used only by --cascade to re-invoke the whole
# loop (untouched) per tier — mirrors how eval_swe.sh already shells out to
# sandbox.sh by absolute path.
SELF_FILE="$SELF_DIR/sandbox.sh"

usage() {
  cat <<EOF
eidolons sandbox — bounded, delegated edit-run-test loop (adapter, not an engine)

Usage:
  eidolons sandbox check  [--via <cmd>] [--allow-unsafe-host] [--json]
  eidolons sandbox run    [--via <cmd>] [--allow-unsafe-host] [--json] -- <test-cmd...>
  eidolons sandbox loop   --tests <test-cmd> [--fix-hook <cmd>] [--via <cmd>]
                          [--max-attempts N] [--base <ref>] [--out <dir>]
                          [--protect <glob>] [--regression <cmd>] [--reproduction <cmd>]
                          [--k N] [--lint-hook <cmd>] [--holdout <cmd>]
                          [--fresh-context] [--require-red] [--fanout N]
                          [--judge-hook <cmd>] [--cascade <tier1,tier2[,tier3]>]
                          [--allow-test-edits] [--allow-unsafe-host] [--json]
  eidolons sandbox replay <out_dir> [--json]
  eidolons sandbox apply  --proposal <edit-proposal.json> --root <scratch-dir> [--json]

check   Classify the isolation tier of --via and apply the refusal policy
        (untrusted code needs >= container isolation).
run     Run a test command through the delegated sandbox; capture pass/fail.
loop    Bounded edit-run-test loop: run tests -> on fail call --fix-hook (the
        host's LLM/edit step) -> retry, capped at --max-attempts (default 3).
        Emits a candidate diff for review (NEVER commits/merges). On cap-out,
        emits a mandatory VIGIL repair-failed-report and exits 3.
replay  READ-ONLY render of a completed loop's artifacts. Reads loop.json from
        <out_dir> (required), renders final state / per-attempt summary / pass^k
        non-determinism report, and verifies SHA-256 journal integrity against
        the ECL sidecar envelope (if present). NEVER re-executes anything. No
        isolation required (--allow-unsafe-host is not needed).
apply   Deterministically apply an Eidolon's EMITTED edit-proposal (search/replace
        or whole-file) into a SCRATCH --root via the fuzzy applier — the mechanical
        P-phase of the Kupo executor. Requires an explicit --root; NEVER defaults to
        the real tree (diff-not-apply discipline). The model emits intent; this
        deterministic, non-LLM applier reconciles it (small models can't hand-apply).

        loop_contract (roster/aci.yaml) extras:
          --protect <glob>      anchoring tests the fix-hook MUST NOT edit; a
                                mutation aborts the loop + escalates (anti-cheat).
          --regression <cmd>    run FIRST; --reproduction <cmd> runs only if it
          --reproduction <cmd>  passes (regression-first; passing only the new
                                test FAILS).
          --k N                 pass^k: a green candidate must pass N re-runs in a
                                row; a non-deterministic pass is flaky -> BLOCKED.
          --lint-hook <cmd>     run AFTER --fix-hook, BEFORE tests; failing lint
                                short-circuits the iteration with phase:"lint"
                                feedback carrying compile loci (ACI edit-gate).
          --holdout <cmd>       sealed test suite the fix-hook NEVER sees; run
                                ONLY after final=passed; failure → reward-hacked.
          --fresh-context       signal to the fix-hook that each retry should use
                                only localized feedback (no prior transcript).
          --require-red         RED GATE: verify the reproduction test FAILS on
                                the base tree BEFORE any fix attempt. A repro
                                test that already passes is VACUOUS (it cannot
                                anchor a fix) → final=vacuous-reproduction.
          --fanout N            parallel-sample-and-select: N INDEPENDENT fresh-
                                context candidates, each generated from the SAME
                                base tree + the SAME localized base-failure
                                feedback (no self-repair iteration); selection is
                                EXTERNAL — tests + pass^k + holdout + judge pick
                                the survivor. The weak-host alternative to the
                                iterate loop (self-repair degrades on weak
                                hosts). Needs a git repo + --fix-hook.
          --judge-hook <cmd>    external judge run over a PASSING candidate's
                                diff (EIDOLONS_SANDBOX_DIFF) before acceptance;
                                non-zero exit rejects it (layered hack detection
                                — a sealed holdout alone is insufficient).
          --cascade <t1,t2[,t3]>  post-generation tier cascade: run the ENTIRE
                                loop above (attempts, pass^k, fanout — all
                                UNTOUCHED) at t1 with EIDOLONS_SANDBOX_MODEL_TIER=t1
                                exported to --fix-hook/--judge-hook; on success,
                                stop and report cascade_tier_used=t1. If the
                                loop exhausts its attempts without a pass^k
                                green, log an escalation to stderr, reset the
                                tree to --base (same reset the fanout candidates
                                already use), and re-run the WHOLE loop at t2
                                (then t3 if given). Exhausting the last tier
                                keeps the normal cap-out exit code. Tiers are
                                vendor-neutral and MUST be a strictly ascending
                                subsequence of light < standard < deep (2 or 3
                                of them) — the LOOP decides when to escalate,
                                never the model; every pre-generation difficulty
                                router is ML-shaped, run-cheap→verify→escalate
                                is the only deterministic-capable routing class.
                                The sandbox stays model-agnostic: --fix-hook
                                (and --judge-hook) is the one that maps a tier
                                name to a concrete model. Omit --cascade and
                                EIDOLONS_SANDBOX_MODEL_TIER is never exported —
                                byte-identical to pre-cascade behavior.
          --allow-test-edits    Opt OUT of the default-on test-tamper ratchet
                                (see below). Logged once; use only when the
                                fix-hook is trusted to edit its own tests.
        The fix-hook receives EIDOLONS_SANDBOX_FEEDBACK (structured JSON: failing
        markers, file:line loci, full-log path) — localized, not a raw tail.

        Test-file anti-tamper ratchet (ON by default; --allow-test-edits opts
        out): at loop start, every file under the workdir whose name matches
        *test*/*spec* (case-insensitive; .git and --out excluded; capped at
        5000 files with a warning) is snapshotted as path+sha256. After EACH
        candidate patch (--fix-hook call, in both iterate and --fanout modes),
        BEFORE the verifier runs, the snapshot is rechecked: a missing or
        hash-changed file REJECTS that attempt/candidate as test-tamper (a
        failed attempt, not a loop abort — the fix-hook gets another try) and
        is counted in the summary as tamper_rejections=N. New test files are
        always allowed (adding tests is legitimate). Strong policies routinely
        exploit weak verifiers by deleting/editing the failing test instead of
        fixing the code; the verifier must confirm the frozen checks are the
        ones that actually ran.

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
  check|run|loop|replay|apply) ;;
  *) die "Unknown subcommand: $SUB (want: check | run | loop | replay | apply). See 'eidolons sandbox --help'" ;;
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
LINT_HOOK=""
HOLDOUT=""
FRESH_CONTEXT=false
REQUIRE_RED=false
FANOUT=1
JUDGE_HOOK=""
CASCADE=""
ALLOW_TEST_EDITS=false
TEST_CMD=()
REPLAY_OUT_DIR=""
PROPOSAL=""
ROOT_DIR=""
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
    --lint-hook)         LINT_HOOK="${2:-}"; shift 2 ;;
    --holdout)           HOLDOUT="${2:-}"; shift 2 ;;
    --fresh-context)     FRESH_CONTEXT=true; shift ;;
    --require-red)       REQUIRE_RED=true; shift ;;
    --fanout)            FANOUT="${2:-1}"; shift 2 ;;
    --judge-hook)        JUDGE_HOOK="${2:-}"; shift 2 ;;
    --cascade)           CASCADE="${2:-}"; shift 2 ;;
    --allow-test-edits)  ALLOW_TEST_EDITS=true; shift ;;
    --proposal)          PROPOSAL="${2:-}"; shift 2 ;;
    --root)              ROOT_DIR="${2:-}"; shift 2 ;;
    --)                  _after_dd=true; shift ;;
    -h|--help)           usage; exit 0 ;;
    -*)                  die "Unknown option: $1" ;;
    *)
      # replay: first positional is <out_dir>; all other subcommands use TEST_CMD.
      if [[ "$SUB" == "replay" && -z "$REPLAY_OUT_DIR" ]]; then
        REPLAY_OUT_DIR="$1"; shift
      else
        TEST_CMD+=("$1"); shift
      fi
      ;;
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
  # sed -E (ERE): BSD/macOS sed does NOT support the GNU `\?` quantifier in BRE,
  # so the optional comma must use ERE `?` or the substitution silently no-ops.
  loci_bats="$(grep -oE 'in test file [A-Za-z0-9_./-]+,? line [0-9]+' "$logf" 2>/dev/null \
    | sed -E 's/in test file ([^ ,]*),? line ([0-9]+)/\1:\2/' || true)"
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

# ── Sealed holdout evaluator: run ONCE after final=passed; the fix-hook NEVER
# sees this command (it is never exported to the fix-hook env block). If it
# fails while visible tests passed = reward-hacked (evaluator-gaming). The
# command is materialised TRANSIENTLY under OUT_DIR only for the eval itself
# (argv-style --via wrappers need a file to exec) and removed before control
# can ever return to a fix-hook — the seal against the fix-hook holds. ──────────
_eval_holdout() {
  local logdest="$1" hf="$OUT_DIR/.holdout-run.sh" res
  printf '%s\n' "$HOLDOUT" > "$hf"
  res="$(_run_in_sandbox "sh $hf" "$logdest")"
  rm -f "$hf"
  printf '%s' "$res" | jq -c '. + {phase:"holdout"}'
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

# ── pass^k re-run verifier: given an initial PASSING result JSON, re-run the
# eval (K-1) more times. Echoes {flaky:<bool>, passk_runs:[...]}. Used by the
# fanout path; the iterate path keeps its original inline block. ───────────────
_passk_verify() {
  local first="$1" pkr kk fl=false r2 r2p r2rc
  pkr="$(jq -nc --argjson r "$first" '[{run:1, passed:$r.passed, exit_code:$r.exit_code}]')"
  kk=1
  while [[ "$kk" -lt "$K" ]]; do
    kk=$((kk + 1))
    r2="$(_eval_once "$OUT_DIR/full-log.txt")"
    r2p="$(printf '%s' "$r2" | jq -r '.passed')"
    r2rc="$(printf '%s' "$r2" | jq -r '.exit_code')"
    pkr="$(printf '%s' "$pkr" | jq -c --argjson ki "$kk" \
      --argjson rp "$([ "$r2p" = "true" ] && printf 'true' || printf 'false')" \
      --argjson rc2 "${r2rc:-1}" \
      '. + [{run:$ki, passed:$rp, exit_code:$rc2}]')"
    if [[ "$r2p" != "true" ]]; then fl=true; break; fi
  done
  jq -nc \
    --argjson fl "$([ "$fl" = true ] && printf 'true' || printf 'false')" \
    --argjson pkr "$pkr" '{flaky:$fl, passk_runs:$pkr}'
  return 0
}

# ── External judge over a PASSING candidate (layered hack detection: a sealed
# holdout alone is insufficient — heuristic non-solutions can pass it; a diff-
# review judge catches what execution filters miss). The judge READS the diff +
# feedback; it NEVER edits the tree. exit 0 = approved, non-zero = rejected. ───
_judge_candidate() {
  local jdiff="$OUT_DIR/judge-candidate.diff" jrc=0
  if [[ "$have_git" == true ]]; then
    git diff "${base_sha:-$BASE}" > "$jdiff" 2>/dev/null || git diff > "$jdiff" 2>/dev/null || true
  else
    : > "$jdiff"
  fi
  # Judge stdout/stderr → judge-log.txt (a chatty LLM judge must never corrupt
  # the loop's --json ledger on stdout).
  EIDOLONS_SANDBOX_DIFF="$jdiff" \
  EIDOLONS_SANDBOX_FEEDBACK="$OUT_DIR/feedback.json" \
  EIDOLONS_SANDBOX_BASE="$base_sha" \
  EIDOLONS_SANDBOX_OUT="$OUT_DIR" \
    bash -c "$JUDGE_HOOK" >"$OUT_DIR/judge-log.txt" 2>&1 || jrc=$?
  return "$jrc"
}

# ── Fanout tree reset: every candidate starts from the SAME base tree. Restores
# tracked files to --base and removes ONLY untracked files a prior candidate
# created (compared against the pre-fanout snapshot — pre-existing untracked
# files like runner scripts / the harness's own .swe-test.sh MUST survive).
# Sandbox artifacts (the --out dir, .eidolons/) survive too. ────────────────────
_untracked_snapshot() {
  git ls-files --others --exclude-standard 2>/dev/null | sort > "$OUT_DIR/.untracked-base" || true
  return 0
}
_tree_reset() {
  git checkout -f "${base_sha:-HEAD}" -- . 2>/dev/null || true
  [[ -f "$OUT_DIR/.untracked-base" ]] || return 0
  git ls-files --others --exclude-standard 2>/dev/null | sort \
    | comm -13 "$OUT_DIR/.untracked-base" - 2>/dev/null \
    | while IFS= read -r _trf; do
        case "$_trf" in
          "$OUT_DIR"/*|.eidolons/*) : ;;
          *) rm -f "$_trf" ;;
        esac
      done
  return 0
}

# ── Test-file anti-tamper ratchet ──────────────────────────────────────────────
# Weak-verifier exploitation counter-measure: a strong policy can pass a weak
# verifier by deleting/editing the failing test instead of fixing the code. The
# ratchet snapshots (path+sha256) every workdir file whose name matches the
# common test-file convention (*test*/*spec*, case-insensitive) at loop start,
# then rechecks after every candidate patch, BEFORE the verifier runs. Missing
# or hash-changed files = tamper (that attempt/candidate is REJECTED, not the
# whole loop — the fix-hook gets another try). New test files are always fine.
_TEST_GLOB_CAP=5000

_ratchet_find_files() {
  # Excludes .git (noise/perf) and $OUT_DIR (the loop's own artifacts never
  # look like tests, but excluding them keeps the manifest honestly scoped to
  # the workdir under test). Case-insensitive *test*/*spec* filename match.
  find . -path './.git' -prune -o -path "./$OUT_DIR" -prune -o -type f \
    \( -iname '*test*' -o -iname '*spec*' \) -print 2>/dev/null \
    | sed 's#^\./##' | sort
}

_ratchet_snapshot() {
  local manifest="$OUT_DIR/.test-manifest.json" files total tmp f h
  files="$(_ratchet_find_files)"
  total=0
  [[ -n "$files" ]] && total="$(printf '%s\n' "$files" | grep -c .)"
  if [[ "$total" -gt "$_TEST_GLOB_CAP" ]]; then
    [[ "$OUT" != "json" ]] && warn "sandbox loop: test-tamper ratchet — $total test-glob files found; capping the snapshot at $_TEST_GLOB_CAP"
    files="$(printf '%s\n' "$files" | head -n "$_TEST_GLOB_CAP")"
  fi
  tmp="$(mktemp)"
  : > "$tmp"
  if [[ -n "$files" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      h="$(sha256_file "$f" 2>/dev/null || echo "")"
      printf '%s\t%s\n' "$f" "$h" >> "$tmp"
    done <<< "$files"
  fi
  jq -R -s -c '[split("\n") | .[] | select(length>0) | split("\t") | {path:.[0], sha256:.[1]}]' "$tmp" > "$manifest" 2>/dev/null \
    || printf '[]' > "$manifest"
  rm -f "$tmp"
  return 0
}

# Echoes one "missing: <path>" / "changed: <path>" line per violation (empty
# output = clean). Always returns 0 — callers test output emptiness, not $?.
_ratchet_check() {
  local manifest="$OUT_DIR/.test-manifest.json" n i path expect actual
  [[ -f "$manifest" ]] || return 0
  n="$(jq -r 'length' "$manifest" 2>/dev/null || echo 0)"
  i=0
  while [[ "$i" -lt "$n" ]]; do
    path="$(jq -r ".[$i].path" "$manifest" 2>/dev/null || echo "")"
    expect="$(jq -r ".[$i].sha256" "$manifest" 2>/dev/null || echo "")"
    if [[ -n "$path" ]]; then
      if [[ ! -f "$path" ]]; then
        printf 'missing: %s\n' "$path"
      else
        actual="$(sha256_file "$path" 2>/dev/null || echo "")"
        [[ "$actual" != "$expect" ]] && printf 'changed: %s\n' "$path"
      fi
    fi
    i=$((i + 1))
  done
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
    [[ "$FANOUT" -ge 1 ]] 2>/dev/null || die "--fanout must be >= 1"
    if [[ "$FANOUT" -gt 1 ]]; then
      [[ -n "$FIX_HOOK" ]] || die "--fanout needs a --fix-hook (the candidate generator)"
    fi

    # ── --cascade: validate the tier list (2-3 members, strictly ascending,
    # drawn from the closed vendor-neutral ladder light < standard < deep). ────
    CASCADE_TIERS=()
    if [[ -n "$CASCADE" ]]; then
      _casc_old_ifs="$IFS"; IFS=','
      # shellcheck disable=SC2206
      CASCADE_TIERS=($CASCADE)
      IFS="$_casc_old_ifs"
      [[ "${#CASCADE_TIERS[@]}" -ge 2 && "${#CASCADE_TIERS[@]}" -le 3 ]] \
        || die "--cascade needs 2-3 comma-separated tiers from light,standard,deep (got: $CASCADE)"
      _casc_prev_rank=0
      for _casc_t in "${CASCADE_TIERS[@]}"; do
        case "$_casc_t" in
          light)    _casc_rank=1 ;;
          standard) _casc_rank=2 ;;
          deep)     _casc_rank=3 ;;
          *) die "--cascade: unknown tier '$_casc_t' (want: light, standard, deep)" ;;
        esac
        [[ "$_casc_rank" -gt "$_casc_prev_rank" ]] \
          || die "--cascade tiers must be strictly ascending (light < standard < deep); got: $CASCADE"
        _casc_prev_rank="$_casc_rank"
      done
    fi

    # ── --cascade dispatch: re-invoke THIS script once per tier, wrapping the
    # entire loop below (attempts/pass^k/fanout — UNTOUCHED) untouched. The loop
    # decides escalation, never the model; the fix-hook maps tier -> a concrete
    # model. Runs as a SEPARATE process per tier so EIDOLONS_SANDBOX_MODEL_TIER
    # is exported into that process's environment (and inherited by its own
    # --fix-hook/--judge-hook `bash -c` calls) with zero changes to the loop's
    # own fix-hook/judge-hook invocation code. ─────────────────────────────────
    if [[ "${#CASCADE_TIERS[@]}" -gt 0 ]]; then
      _casc_out_root="$OUT_DIR"
      [[ -z "$_casc_out_root" ]] && _casc_out_root=".eidolons/sandbox/run-$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$_casc_out_root"

      _casc_have_git=false
      git rev-parse --git-dir >/dev/null 2>&1 && _casc_have_git=true
      _casc_base_sha=""
      [[ "$_casc_have_git" == true ]] && _casc_base_sha="$(git rev-parse "$BASE" 2>/dev/null || echo "")"
      if [[ "$_casc_have_git" == true ]]; then
        OUT_DIR="$_casc_out_root"; base_sha="$_casc_base_sha"
        _untracked_snapshot   # baseline for the fresh-workdir reset between tiers
      fi

      _casc_ledger="{}"; _casc_child_rc=0; _casc_tier_used=""; _casc_first=true
      for _casc_tier in "${CASCADE_TIERS[@]}"; do
        if [[ "$_casc_first" != true && "$_casc_have_git" == true ]]; then
          OUT_DIR="$_casc_out_root"; base_sha="$_casc_base_sha"
          _tree_reset   # fresh workdir before the next tier (same reset --fanout uses)
        fi
        _casc_first=false
        _casc_tier_out="$_casc_out_root/cascade-$_casc_tier"
        mkdir -p "$_casc_tier_out"

        _casc_args=()
        [[ -n "$TESTS" ]]              && _casc_args+=(--tests "$TESTS")
        [[ -n "$REGRESSION" ]]         && _casc_args+=(--regression "$REGRESSION")
        [[ -n "$REPRODUCTION" ]]       && _casc_args+=(--reproduction "$REPRODUCTION")
        [[ -n "$FIX_HOOK" ]]           && _casc_args+=(--fix-hook "$FIX_HOOK")
        [[ -n "$VIA" ]]                && _casc_args+=(--via "$VIA")
        [[ "$ALLOW_UNSAFE" == true ]]  && _casc_args+=(--allow-unsafe-host)
        _casc_args+=(--max-attempts "$MAX_ATTEMPTS")
        _casc_args+=(--base "$BASE")
        [[ -n "$PROTECT" ]]            && _casc_args+=(--protect "$PROTECT")
        _casc_args+=(--k "$K")
        [[ -n "$LINT_HOOK" ]]          && _casc_args+=(--lint-hook "$LINT_HOOK")
        [[ -n "$HOLDOUT" ]]            && _casc_args+=(--holdout "$HOLDOUT")
        [[ "$FRESH_CONTEXT" == true ]] && _casc_args+=(--fresh-context)
        [[ "$REQUIRE_RED" == true ]]   && _casc_args+=(--require-red)
        _casc_args+=(--fanout "$FANOUT")
        [[ -n "$JUDGE_HOOK" ]]         && _casc_args+=(--judge-hook "$JUDGE_HOOK")
        [[ "$ALLOW_TEST_EDITS" == true ]] && _casc_args+=(--allow-test-edits)
        _casc_args+=(--out "$_casc_tier_out" --json)
        if [[ -z "$TESTS" && ${#TEST_CMD[@]} -gt 0 ]]; then
          _casc_args+=(--)
          _casc_args+=("${TEST_CMD[@]}")
        fi

        [[ "$OUT" != "json" ]] && [[ "$_casc_tier" != "${CASCADE_TIERS[0]}" ]] && \
          warn "sandbox loop: cascade escalating to tier=$_casc_tier (previous tier exhausted its attempts without a pass^k green)"
        _casc_child_rc=0
        _casc_ledger="$(EIDOLONS_SANDBOX_MODEL_TIER="$_casc_tier" bash "$SELF_FILE" loop "${_casc_args[@]}")" || _casc_child_rc=$?
        _casc_final="$(printf '%s' "$_casc_ledger" | jq -r '.final // "error"' 2>/dev/null || echo error)"
        if [[ "$_casc_final" == "passed" ]]; then
          _casc_tier_used="$_casc_tier"
          break
        fi
        [[ "$OUT" != "json" ]] && warn "sandbox loop: cascade tier=$_casc_tier exhausted (final=$_casc_final)"
      done

      _casc_out_ledger="$(printf '%s' "$_casc_ledger" | jq -c --arg t "$_casc_tier_used" '. + {cascade_tier_used:$t}')"
      printf '%s\n' "$_casc_out_ledger" > "$_casc_out_root/loop.json"
      _casc_sha="$( { shasum -a 256 "$_casc_out_root/loop.json" 2>/dev/null || sha256sum "$_casc_out_root/loop.json" 2>/dev/null; } | awk '{print $1}' )"
      _casc_size="$(cksum "$_casc_out_root/loop.json" 2>/dev/null | awk '{print $2}' || echo "0")"
      jq -nc --arg sha "${_casc_sha:-}" --argjson sz "${_casc_size:-0}" --arg out "$_casc_out_root" \
        '{envelope_version:"1.0", performative:"inform",
          sender:{eidolon:"eidolons-sandbox",version:"1.0"}, receiver:{eidolon:"",version:""},
          artifact:{kind:"loop-ledger",path:"loop.json"},
          integrity:{method:"sha256",value:$sha,size_bytes:$sz}, trace:{out_dir:$out}}' \
        > "$_casc_out_root/loop.json.envelope.json"

      if [[ "$OUT" == "json" ]]; then
        printf '%s\n' "$_casc_out_ledger"
      else
        printf '%ssandbox loop (cascade)%s  %s  cascade_tier_used=%s  tiers=%s\n' \
          "${BOLD:-}" "${RESET:-}" "$(printf '%s' "$_casc_out_ledger" | jq -r '.final')" \
          "${_casc_tier_used:-<none>}" "$CASCADE"
        if [[ -n "$_casc_tier_used" ]]; then
          ok "cascade: tests pass at tier=$_casc_tier_used — review the candidate diff and apply it yourself (diff-not-apply)"
        else
          warn "cascade: all tiers ($CASCADE) exhausted — see $_casc_out_root"
        fi
      fi
      exit "$_casc_child_rc"
    fi

    # Output dir (diff-not-apply artifacts + VIGIL hand-off live here).
    if [[ -z "$OUT_DIR" ]]; then OUT_DIR=".eidolons/sandbox/run-$(date +%Y%m%d-%H%M%S)"; fi
    mkdir -p "$OUT_DIR"

    have_git=false
    if git rev-parse --git-dir >/dev/null 2>&1; then have_git=true; fi
    base_sha=""
    [[ "$have_git" == true ]] && base_sha="$(git rev-parse "$BASE" 2>/dev/null || echo "")"
    if [[ "$FANOUT" -gt 1 && "$have_git" != true ]]; then
      die "--fanout needs a git repo (every candidate starts from the same base tree)"
    fi

    # Anti-reward-hacking: baseline signature of the protected anchoring tests.
    protect_baseline="$(_protect_snapshot)"

    # ── Test-file anti-tamper ratchet (default-on; --allow-test-edits opts out).
    # Snapshot BEFORE attempt 1 / candidate 1 — see the loop-start note above.
    TAMPER_REJECTIONS=0
    if [[ "$ALLOW_TEST_EDITS" == true ]]; then
      [[ "$OUT" != "json" ]] && warn "sandbox loop: --allow-test-edits — the test-tamper ratchet is DISABLED for this run"
    else
      _ratchet_snapshot
    fi

    # ── Red gate (--require-red): a reproduction test that PASSES on the base
    # tree is VACUOUS — it does not capture the bug and cannot anchor a fix
    # (TDFlow: patching is near-solved when the repro test is RIGHT; repro-test
    # validity is the bottleneck). Verify red FIRST, before any fix attempt. ───
    red_gate=""
    if [[ "$REQUIRE_RED" == true ]]; then
      [[ -n "$REPRODUCTION" || -n "$TESTS" ]] || die "--require-red needs --reproduction (or --tests)"
      if [[ -n "$REPRODUCTION" ]]; then
        _red_result="$(_run_in_sandbox "$REPRODUCTION" "$OUT_DIR/red-gate-log.txt")"
      else
        # --tests path: use the argv form (empty cmd_str → TEST_CMD array), the
        # same execution shape the loop itself uses — an argv-style --via wrapper
        # would mis-exec a multi-word command string and fake a "red" verdict.
        _red_result="$(_run_in_sandbox "" "$OUT_DIR/red-gate-log.txt")"
      fi
      if [[ "$(printf '%s' "$_red_result" | jq -r '.passed')" == "true" ]]; then
        red_gate="vacuous"
        [[ "$OUT" != "json" ]] && warn "sandbox loop: --require-red FAILED — the reproduction test PASSES on the base tree (vacuous: it cannot anchor a fix)"
      else
        red_gate="verified-red"
        # Seed feedback.json from the verified-red run (attempt 0): the first
        # fix-hook call / every fanout candidate reads the SAME localized
        # base-failure signal.
        printf '%s' "$_red_result" | jq -r '.output_tail' > "$OUT_DIR/last-output.txt"
        printf '%s' "$_red_result" | jq -c \
          '{contract_version:"1.0", attempt:0, exit_code:.exit_code, phase:"red-gate",
            passed:false, flaky:false, failing:.failing, loci:.loci,
            test_name:(.test_name // []), assertion:(.assertion // []),
            full_log:"red-gate-log.txt", output_tail:.output_tail}' > "$OUT_DIR/feedback.json"
      fi
    fi

    attempts="[]"
    final="capped"
    last_flaky=false
    _lint_pending=false
    _ratchet_pending=false
    selected_candidate=0
    judge_verdict=""
    n=0
    if [[ "$red_gate" == "vacuous" ]]; then
      # Red gate tripped: no fix attempt may run against a vacuous repro test.
      final="vacuous-reproduction"
    elif [[ "$FANOUT" -gt 1 ]]; then
      # ── FANOUT (parallel-sample-and-select): N INDEPENDENT fresh-context
      # candidates, each generated from the SAME base tree + the SAME localized
      # base-failure feedback. NO self-repair iteration (feeding failures back
      # degrades on weak hosts — RLEF/self-repair literature); selection is
      # EXTERNAL: tests + pass^k + sealed holdout + judge pick the survivor
      # (R2E-Gym hybrid-verifier selection). ────────────────────────────────────
      if [[ ! -f "$OUT_DIR/feedback.json" ]]; then
        # No red gate ran — seed the base-failure feedback with one eval.
        _seed="$(_eval_once "$OUT_DIR/full-log.txt")"
        if [[ "$(printf '%s' "$_seed" | jq -r '.passed')" == "true" ]]; then
          # Nothing to fix: the visible suite already passes on the base tree.
          final="passed"; n=1
          attempts="$(printf '%s' "$attempts" | jq --argjson r "$_seed" \
            '. + [{attempt:1, candidate:0, passed:true, exit_code:$r.exit_code,
                   duration_s:($r.duration_s // 0), phase:($r.phase // "tests"),
                   flaky:false, passk_runs:[]}]')"
        else
          printf '%s' "$_seed" | jq -r '.output_tail' > "$OUT_DIR/last-output.txt"
          printf '%s' "$_seed" | jq -c \
            '{contract_version:"1.0", attempt:0, exit_code:.exit_code, phase:.phase,
              passed:false, flaky:false, failing:.failing, loci:.loci,
              test_name:(.test_name // []), assertion:(.assertion // []),
              full_log:"full-log.txt", output_tail:.output_tail}' > "$OUT_DIR/feedback.json"
        fi
      fi
      _last_reject=""
      _untracked_snapshot
      ci=0
      while [[ "$final" != "passed" && "$ci" -lt "$FANOUT" ]]; do
        ci=$((ci + 1)); n="$ci"
        _tree_reset
        [[ "$OUT" != "json" ]] && warn "sandbox loop: fanout candidate $ci/$FANOUT — invoking --fix-hook (fresh context, base tree)"
        _fh_rc=0
        EIDOLONS_SANDBOX_FEEDBACK="$OUT_DIR/feedback.json" \
        EIDOLONS_SANDBOX_FULL_LOG="$OUT_DIR/full-log.txt" \
        EIDOLONS_SANDBOX_LAST_OUTPUT="$OUT_DIR/last-output.txt" \
        EIDOLONS_SANDBOX_ATTEMPT="$ci" \
        EIDOLONS_SANDBOX_BASE="$base_sha" \
        EIDOLONS_SANDBOX_FRESH_CONTEXT="true" \
        EIDOLONS_SANDBOX_CANDIDATE="$ci" \
        EIDOLONS_SANDBOX_FANOUT="$FANOUT" \
          bash -c "$FIX_HOOK" >&2 || _fh_rc=$?
        # fresh-context is FORCED in fanout (candidate independence is the point);
        # stdout → stderr so a chatty hook never corrupts the --json ledger.
        [[ "$_fh_rc" -ne 0 && "$OUT" != "json" ]] && warn "sandbox loop: --fix-hook returned $_fh_rc (continuing to evaluate the candidate)"
        if [[ -n "$PROTECT" ]] && [[ "$(_protect_snapshot)" != "$protect_baseline" ]]; then
          final="protected-tests-mutated"
          [[ "$OUT" != "json" ]] && warn "sandbox loop: candidate $ci MUTATED a protected anchoring test (--protect) — ABORT + escalate (anti-reward-hacking)"
          break
        fi
        # Test-file anti-tamper ratchet per candidate (default-on): a candidate
        # that deletes/edits a snapshotted test file is REJECTED, not fatal —
        # the next candidate (fanout does not self-repair) starts fresh.
        if [[ "$ALLOW_TEST_EDITS" != true ]]; then
          _ratchet_violations="$(_ratchet_check)"
          if [[ -n "$_ratchet_violations" ]]; then
            TAMPER_REJECTIONS=$((TAMPER_REJECTIONS + 1))
            [[ "$OUT" != "json" ]] && warn "sandbox loop: candidate $ci TAMPERED with a snapshotted test file — REJECTED as test-tamper"
            attempts="$(printf '%s' "$attempts" | jq --argjson n "$ci" \
              '. + [{attempt:$n, candidate:$n, passed:false, exit_code:1, duration_s:0,
                     phase:"test-tamper", flaky:false, passk_runs:[], rejected:"test-tamper"}]')"
            git diff "${base_sha:-$BASE}" > "$OUT_DIR/candidate-$ci.diff" 2>/dev/null || true
            continue
          fi
        fi
        # Lint gate per candidate: a candidate failing lint is REJECTED outright
        # (fanout candidates do not self-repair).
        if [[ -n "$LINT_HOOK" ]]; then
          _lint_rc=0
          bash -c "$LINT_HOOK" >"$OUT_DIR/lint-log.txt" 2>&1 || _lint_rc=$?
          if [[ "$_lint_rc" -ne 0 ]]; then
            [[ "$OUT" != "json" ]] && warn "sandbox loop: candidate $ci failed the lint gate — REJECTED"
            attempts="$(printf '%s' "$attempts" | jq --argjson n "$ci" \
              '. + [{attempt:$n, candidate:$n, passed:false, exit_code:1, duration_s:0,
                     phase:"lint", flaky:false, passk_runs:[], rejected:"lint"}]')"
            git diff "${base_sha:-$BASE}" > "$OUT_DIR/candidate-$ci.diff" 2>/dev/null || true
            continue
          fi
        fi
        result="$(_eval_once "$OUT_DIR/full-log.txt")"
        passed="$(printf '%s' "$result" | jq -r '.passed')"
        passk_runs="[]"
        _cand_flaky=false
        if [[ "$passed" == "true" && "$K" -gt 1 ]]; then
          _pk="$(_passk_verify "$result")"
          passk_runs="$(printf '%s' "$_pk" | jq -c '.passk_runs')"
          if [[ "$(printf '%s' "$_pk" | jq -r '.flaky')" == "true" ]]; then
            passed="false"; _cand_flaky=true; _last_reject="flaky"
            [[ "$OUT" != "json" ]] && warn "sandbox loop: candidate $ci passed once but is FLAKY across k=$K — REJECTED"
          fi
        elif [[ "$passed" == "true" ]]; then
          passk_runs="$(printf '%s' "$result" | jq -c '[{run:1, passed:.passed, exit_code:.exit_code}]')"
        fi
        attempts="$(printf '%s' "$attempts" | jq --argjson n "$ci" --argjson r "$result" \
          --argjson pkruns "$passk_runs" \
          --argjson fl "$([ "$_cand_flaky" = true ] && printf 'true' || printf 'false')" \
          '. + [{attempt:$n, candidate:$n, passed:(if $fl then false else $r.passed end),
                 exit_code:$r.exit_code, duration_s:($r.duration_s // 0),
                 phase:($r.phase // "tests"), flaky:$fl, passk_runs:$pkruns}]')"
        if [[ "$passed" == "true" ]]; then
          # Sealed holdout per candidate: a reward-hacked candidate is REJECTED,
          # not terminal — another independent candidate may genuinely solve it.
          if [[ -n "$HOLDOUT" ]]; then
            _hout_result="$(_eval_holdout "$OUT_DIR/holdout-log.txt")"
            if [[ "$(printf '%s' "$_hout_result" | jq -r '.passed')" != "true" ]]; then
              _last_reject="reward-hacked"
              attempts="$(printf '%s' "$attempts" | jq --argjson i "$ci" \
                'map(if .attempt == $i then . + {rejected:"reward-hacked"} else . end)')"
              [[ "$OUT" != "json" ]] && warn "sandbox loop: candidate $ci passed visible tests but FAILED the sealed holdout — REJECTED (reward-hacking)"
              git diff "${base_sha:-$BASE}" > "$OUT_DIR/candidate-$ci.diff" 2>/dev/null || true
              continue
            fi
          fi
          if [[ -n "$JUDGE_HOOK" ]]; then
            if _judge_candidate; then judge_verdict="approved"
            else
              judge_verdict="rejected"; _last_reject="judge-rejected"
              attempts="$(printf '%s' "$attempts" | jq --argjson i "$ci" \
                'map(if .attempt == $i then . + {rejected:"judge-rejected"} else . end)')"
              [[ "$OUT" != "json" ]] && warn "sandbox loop: candidate $ci REJECTED by the --judge-hook — trying the next candidate"
              git diff "${base_sha:-$BASE}" > "$OUT_DIR/candidate-$ci.diff" 2>/dev/null || true
              continue
            fi
          fi
          final="passed"; selected_candidate="$ci"
          break
        fi
        git diff "${base_sha:-$BASE}" > "$OUT_DIR/candidate-$ci.diff" 2>/dev/null || true
      done
      # All candidates exhausted: surface the most informative rejection reason.
      if [[ "$final" == "capped" && -n "$_last_reject" ]]; then
        case "$_last_reject" in
          reward-hacked)  final="reward-hacked" ;;
          judge-rejected) final="judge-rejected" ;;
          flaky)          final="flaky" ;;
        esac
      fi
    else
    while [[ "$n" -lt "$MAX_ATTEMPTS" ]]; do
      n=$((n + 1))
      last_flaky=false
      if [[ "$_lint_pending" == "true" || "$_ratchet_pending" == "true" ]]; then
        # The previous attempt's fix-hook edit FAILED the lint gate OR the
        # test-tamper ratchet. Do NOT re-run the tests on a known-bad/rejected
        # edit (ACI edit-gate: reject invalid code BEFORE testing — SWE-agent
        # edit-with-linter). The phase-specific feedback from the prior
        # iteration stays the active feedback the fix-hook reads. Record the
        # rejected attempt, then fall straight through to the fix-hook re-invocation.
        _pending_phase="lint"
        [[ "$_ratchet_pending" == "true" ]] && _pending_phase="test-tamper"
        _lint_pending=false
        _ratchet_pending=false
        passed="false"
        attempts="$(printf '%s' "$attempts" | jq --argjson n "$n" --arg phase "$_pending_phase" \
          '. + [{attempt:$n, passed:false, exit_code:1, duration_s:0, phase:$phase, flaky:false, passk_runs:[]}]')"
      else
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
      fi

      if [[ "$passed" == "true" ]]; then
        final="passed"
        # Sealed holdout gate: the fix-hook never sees --holdout (it is not in
        # the env block above). Run ONLY after visible tests pass. Failure here =
        # reward-hacked (the coder passed the visible suite but failed the sealed
        # oracle — evaluator-gaming caught).
        if [[ -n "$HOLDOUT" ]]; then
          _hout_log="$OUT_DIR/holdout-log.txt"
          _hout_result="$(_eval_holdout "$_hout_log")"
          _hout_passed="$(printf '%s' "$_hout_result" | jq -r '.passed')"
          if [[ "$_hout_passed" != "true" ]]; then
            final="reward-hacked"
            [[ "$OUT" != "json" ]] && warn "sandbox loop: SEALED HOLDOUT FAILED — visible tests passed but holdout FAILED (reward-hacking / evaluator-gaming) — BLOCKED"
          fi
        fi
        # External judge gate (layered hack detection): runs only on a candidate
        # that survived visible tests + pass^k + holdout.
        if [[ "$final" == "passed" && -n "$JUDGE_HOOK" ]]; then
          if _judge_candidate; then judge_verdict="approved"
          else
            judge_verdict="rejected"; final="judge-rejected"
            [[ "$OUT" != "json" ]] && warn "sandbox loop: candidate REJECTED by the --judge-hook (suspected non-fix / evaluator-gaming) — BLOCKED"
          fi
        fi
        break
      fi
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
      EIDOLONS_SANDBOX_FRESH_CONTEXT="$FRESH_CONTEXT" \
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

      # Test-file anti-tamper ratchet (default-on): did the fix-hook delete/edit
      # a snapshotted test file? REJECT this attempt (not a loop abort — the
      # fix-hook gets another try, unlike --protect's abort-the-whole-loop).
      if [[ "$ALLOW_TEST_EDITS" != true ]]; then
        _ratchet_violations="$(_ratchet_check)"
        if [[ -n "$_ratchet_violations" ]]; then
          TAMPER_REJECTIONS=$((TAMPER_REJECTIONS + 1))
          [[ "$OUT" != "json" ]] && warn "sandbox loop: attempt $n's --fix-hook TAMPERED with a snapshotted test file — REJECTED as test-tamper (not accepted)"
          jq -nc --argjson n "$n" --arg viol "$_ratchet_violations" \
            '{contract_version:"1.0", attempt:$n, phase:"test-tamper", passed:false,
              exit_code:1, flaky:false, failing:$viol,
              loci:[], test_name:[], assertion:[],
              full_log:"", output_tail:$viol}' > "$OUT_DIR/feedback.json"
          _ratchet_pending=true
          continue
        fi
      fi

      # Lint gate (ACI edit-gate): run --lint-hook AFTER fix-hook + protect check,
      # BEFORE the next test iteration. Failing lint short-circuits this iteration
      # and writes a phase:"lint" feedback artefact with compile loci.
      if [[ -n "$LINT_HOOK" ]]; then
        _lint_log="$OUT_DIR/lint-log.txt"
        _lint_rc=0
        bash -c "$LINT_HOOK" >"$_lint_log" 2>&1 || _lint_rc=$?
        if [[ "$_lint_rc" -ne 0 ]]; then
          [[ "$OUT" != "json" ]] && warn "sandbox loop: --lint-hook failed (exit $_lint_rc) — short-circuiting iteration, writing lint feedback"
          # Extract compile loci from the lint output using the deepened parser.
          _lint_tail="$(tail -n 40 "$_lint_log" 2>/dev/null || true)"
          _lint_loci_colon="$(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' "$_lint_log" 2>/dev/null || true)"
          _lint_loci_sc="$(grep -oE 'In [A-Za-z0-9_./-]+ line [0-9]+:' "$_lint_log" 2>/dev/null \
            | sed 's/In \([^ ]*\) line \([0-9]*\):/\1:\2/' || true)"
          _lint_loci="$(printf '%s\n%s\n' "$_lint_loci_colon" "$_lint_loci_sc" \
            | grep -v '^$' | sort -u | head -n 20 || true)"
          jq -nc --argjson n "$n" --argjson rc "$_lint_rc" \
            --arg loci "$_lint_loci" --arg tail "$_lint_tail" \
            '{contract_version:"1.0", attempt:$n, phase:"lint", passed:false,
              exit_code:$rc, flaky:false, failing:"lint hook failed",
              loci:($loci | split("\n") | map(select(length>0))),
              test_name:[], assertion:[],
              full_log:"lint-log.txt", output_tail:$tail}' > "$OUT_DIR/feedback.json"
          # Short-circuit: flag the next iteration to SKIP the test eval (don't test
          # a known-bad edit) and re-invoke the fix-hook with this lint feedback.
          _lint_pending=true
          continue
        fi
      fi
    done

    # A capped loop whose last attempt was a blocked flaky green reports `flaky`.
    [[ "$final" == "capped" && "$last_flaky" == "true" ]] && final="flaky"
    fi

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
        reward-hacked)            _reason="passed the visible suite but FAILED the sealed holdout (evaluator-gaming) — BLOCKED" ;;
        vacuous-reproduction)     _reason="the reproduction test PASSES on the base tree (--require-red): it does not capture the bug and cannot anchor a fix" ;;
        judge-rejected)           _reason="the external --judge-hook REJECTED the candidate diff (suspected non-fix / evaluator-gaming) — BLOCKED" ;;
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
        echo "- sealed holdout: \`${HOLDOUT:-<none>}\`"
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
      --argjson fanout "$FANOUT" --argjson selected "$selected_candidate" \
      --arg red_gate "$red_gate" --arg judge "$judge_verdict" \
      --argjson tamper_rejections "$TAMPER_REJECTIONS" --arg cascade_tier_used "" \
      '{final:$final, attempts_run:($attempts|length), max_attempts:$max, k:$k,
        protect:$protect, tier:$tier, base:$base, candidate_diff:$diff,
        feedback:$feedback, vigil_handoff:$vigil, out_dir:$out,
        merged:false, attempts:$attempts, passk:$passk,
        fanout:$fanout, selected_candidate:$selected,
        red_gate:$red_gate, judge:$judge,
        tamper_rejections:$tamper_rejections, cascade_tier_used:$cascade_tier_used}')"
    printf '%s\n' "$ledger" > "$OUT_DIR/loop.json"

    # ECL sidecar: loop.json.envelope.json — inform performative, SHA-256 integrity.
    # ECL P0: "SHA-256 is the default integrity algorithm". Computed NON-FATALLY
    # (the loop already succeeded; the envelope is a sidecar — never die here).
    # Reuses the closed-10 `inform` performative (GAP-2 decision); bash 3.2 safe.
    # sender="eidolons-sandbox" (stateless substrate identity); receiver="" (consuming agent,
    # Vivi, unknown at substrate level — R1 residual confirmed: empty string is the safe default).
    _loop_sha="$( { shasum -a 256 "$OUT_DIR/loop.json" 2>/dev/null || sha256sum "$OUT_DIR/loop.json" 2>/dev/null; } | awk '{print $1}' )"
    _loop_sha="${_loop_sha:-}"
    # Portable byte count: cksum prints "checksum size path"; we only need size (field 2).
    _loop_size="$(cksum "$OUT_DIR/loop.json" 2>/dev/null | awk '{print $2}' || echo "0")"
    _loop_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')"
    jq -nc \
      --arg ts "$_loop_ts" \
      --arg sha "$_loop_sha" \
      --argjson sz "$_loop_size" \
      --arg out "$OUT_DIR" \
      '{envelope_version:"1.0",
        performative:"inform",
        sender:{eidolon:"eidolons-sandbox",version:"1.0"},
        receiver:{eidolon:"",version:""},
        artifact:{kind:"loop-ledger",path:"loop.json"},
        integrity:{method:"sha256",value:$sha,size_bytes:$sz},
        trace:{ts:$ts,out_dir:$out}}' > "$OUT_DIR/loop.json.envelope.json"

    if [[ "$OUT" == "json" ]]; then printf '%s\n' "$ledger"
    else
      printf '%ssandbox loop%s  %s  (%s/%s attempts, k=%s, tier=%s, tamper_rejections=%s)\n' "${BOLD:-}" "${RESET:-}" "$final" "$n" "$MAX_ATTEMPTS" "$K" "$TIER" "$TAMPER_REJECTIONS"
      printf '%s' "$attempts" | jq -r '.[] | "  attempt \(.attempt): \(if .passed then "PASS" else "FAIL" end)\(if .flaky then " (FLAKY)" else "" end) [\(.phase)] (\(.duration_s)s)"'
      [[ -n "$diff_path" ]] && printf '  candidate diff (NOT applied): %s\n' "$diff_path"
      if [[ "$final" == "passed" ]]; then ok "tests pass — review the candidate diff and apply it yourself (diff-not-apply)"
      else warn "cap reached — VIGIL hand-off written: $vigil_handoff"; fi
    fi
    [[ "$final" == "passed" ]] && exit 0 || exit 3
    ;;

  # ── apply: deterministic fuzzy edit applier (the Kupo executor's P phase) ────
  apply)
    [[ -n "$PROPOSAL" ]] || die "apply needs --proposal <edit-proposal.json>"
    [[ -n "$ROOT_DIR" ]] || die "apply needs --root <scratch-dir> (NEVER defaults to the real tree)"
    [[ -f "$PROPOSAL" ]] || die "apply: proposal not found: $PROPOSAL"
    [[ -d "$ROOT_DIR" ]] || die "apply: --root is not a directory: $ROOT_DIR"
    rc=0
    result="$(pa_apply_proposal "$PROPOSAL" "$ROOT_DIR")" || rc=$?
    if [[ "$OUT" == "json" ]]; then printf '%s\n' "$result"
    else
      printf '%ssandbox apply%s  applied=%s failed=%s  →  %s\n' "${BOLD:-}" "${RESET:-}" \
        "$(printf '%s' "$result" | jq -r '.applied // 0')" \
        "$(printf '%s' "$result" | jq -r '.failed // 0')" \
        "$(printf '%s' "$result" | jq -r 'if .ok then "ok" else "INCOMPLETE" end')"
      printf '%s' "$result" | jq -r '.results[]? | "  \(.status): \(.op) \(.path) — \(.detail)"'
    fi
    [[ "$rc" -eq 0 ]] && exit 0 || exit 1
    ;;

  # ── replay: read-only render of a completed loop's artifacts ─────────────────
  # NO re-execution. NO isolation required. Reads artifacts, verifies SHA-256
  # journal integrity, reports pass^k determinism. Exits non-zero only on
  # tampered journal (exit 4) or missing/unparseable loop.json (exit 1).
  # (Artifact-level SHA-256 tamper-evidence of the on-disk journal; does NOT
  # change ECL receiver verification semantics — that is ecosystem-coordinated.)
  replay)
    [[ -n "$REPLAY_OUT_DIR" ]] || die "replay needs an <out_dir> argument. Usage: eidolons sandbox replay <out_dir> [--json]"
    [[ -d "$REPLAY_OUT_DIR" ]] || die "replay: directory not found: $REPLAY_OUT_DIR"
    _rp_loop="$REPLAY_OUT_DIR/loop.json"
    [[ -f "$_rp_loop" ]] || die "replay: loop.json not found in $REPLAY_OUT_DIR — has the loop completed?"

    # Validate loop.json is parseable JSON (non-fatal parse attempt).
    _rp_valid=false
    jq -e . "$_rp_loop" >/dev/null 2>&1 && _rp_valid=true
    [[ "$_rp_valid" == true ]] || die "replay: loop.json is not valid JSON in $REPLAY_OUT_DIR"

    # Read core fields from loop.json.
    _rp_final="$(jq -r '.final // "unknown"' "$_rp_loop")"
    _rp_attempts_run="$(jq -r '.attempts_run // 0' "$_rp_loop")"
    _rp_max_attempts="$(jq -r '.max_attempts // 0' "$_rp_loop")"
    _rp_k="$(jq -r '.k // 1' "$_rp_loop")"
    _rp_candidate_diff="$(jq -r '.candidate_diff // ""' "$_rp_loop")"
    _rp_vigil_handoff="$(jq -r '.vigil_handoff // ""' "$_rp_loop")"
    _rp_attempts_json="$(jq -c '.attempts // []' "$_rp_loop")"
    _rp_passk_json="$(jq -c '.passk // {}' "$_rp_loop")"

    # ── Integrity verification (SHA-256 tamper-evidence) ──────────────────────
    _rp_envelope="$REPLAY_OUT_DIR/loop.json.envelope.json"
    _rp_integrity="unverifiable"
    _rp_integrity_detail="no envelope"
    _rp_tampered=false
    if [[ -f "$_rp_envelope" ]]; then
      _rp_env_method="$(jq -r '.integrity.method // ""' "$_rp_envelope" 2>/dev/null || true)"
      _rp_env_sha="$(jq -r '.integrity.value // ""' "$_rp_envelope" 2>/dev/null || true)"
      if [[ "$_rp_env_method" == "sha256" && -n "$_rp_env_sha" ]]; then
        # Recompute SHA-256 of loop.json (non-fatal; empty = cannot compute).
        _rp_actual_sha="$( { shasum -a 256 "$_rp_loop" 2>/dev/null || sha256sum "$_rp_loop" 2>/dev/null; } | awk '{print $1}' )"
        _rp_actual_sha="${_rp_actual_sha:-}"
        if [[ -z "$_rp_actual_sha" ]]; then
          _rp_integrity="unverifiable"
          _rp_integrity_detail="cannot compute sha256 (no shasum/sha256sum)"
        elif [[ "$_rp_actual_sha" == "$_rp_env_sha" ]]; then
          _rp_integrity="VERIFIED"
          _rp_integrity_detail="sha256 matches envelope"
        else
          _rp_integrity="MISMATCH"
          _rp_integrity_detail="journal tampered since the run (expected=$_rp_env_sha actual=$_rp_actual_sha)"
          _rp_tampered=true
        fi
      else
        # Envelope exists but uses a different method (e.g. legacy cksum).
        _rp_integrity="unverifiable"
        _rp_integrity_detail="envelope method is '${_rp_env_method:-unknown}' (not sha256)"
      fi
    fi

    # ── pass^k non-determinism report ─────────────────────────────────────────
    # For each attempt, inspect its passk_runs[]. If any run has passed != all
    # others, the attempt is NON-DETERMINISTIC (flaky).
    _rp_passk_report="[]"
    _rp_any_flaky=false
    _rp_attempt_count="$(printf '%s' "$_rp_attempts_json" | jq -r 'length')"
    _rp_i=0
    while [[ "$_rp_i" -lt "$_rp_attempt_count" ]]; do
      _rp_att="$(printf '%s' "$_rp_attempts_json" | jq -c ".[$_rp_i]")"
      _rp_att_n="$(printf '%s' "$_rp_att" | jq -r '.attempt // 0')"
      _rp_att_passed="$(printf '%s' "$_rp_att" | jq -r '.passed // false')"
      _rp_pkruns="$(printf '%s' "$_rp_att" | jq -c '.passk_runs // []')"
      _rp_pk_len="$(printf '%s' "$_rp_pkruns" | jq -r 'length')"
      _rp_det="deterministic"
      if [[ "$_rp_pk_len" -gt 1 ]]; then
        # Check if all passed values are identical.
        _rp_unique="$(printf '%s' "$_rp_pkruns" | jq -r '[.[].passed] | unique | length')"
        if [[ "$_rp_unique" -gt 1 ]]; then
          _rp_det="NON-DETERMINISTIC"
          _rp_any_flaky=true
        fi
      fi
      _rp_passk_report="$(printf '%s' "$_rp_passk_report" | jq -c \
        --argjson n "$_rp_att_n" --arg det "$_rp_det" --argjson p "$_rp_att_passed" \
        --argjson pkr "$_rp_pkruns" \
        '. + [{attempt:$n, passed:$p, determinism:$det, passk_runs:$pkr}]')"
      _rp_i=$((_rp_i + 1))
    done
    _rp_passk_determinism="deterministic"
    [[ "$_rp_any_flaky" == true ]] && _rp_passk_determinism="NON-DETERMINISTIC (flaky pass^k detected)"

    if [[ "$OUT" == "json" ]]; then
      jq -nc \
        --arg out_dir "$REPLAY_OUT_DIR" \
        --arg final "$_rp_final" \
        --argjson attempts_run "$_rp_attempts_run" \
        --argjson max_attempts "$_rp_max_attempts" \
        --argjson k "$_rp_k" \
        --arg passk_determinism "$_rp_passk_determinism" \
        --arg integrity "$_rp_integrity" \
        --arg integrity_detail "$_rp_integrity_detail" \
        --arg candidate_diff "$_rp_candidate_diff" \
        --arg vigil_handoff "$_rp_vigil_handoff" \
        --argjson attempts "$_rp_passk_report" \
        '{out_dir:$out_dir, final:$final, attempts_run:$attempts_run,
          max_attempts:$max_attempts, k:$k,
          passk_determinism:$passk_determinism,
          integrity:$integrity, integrity_detail:$integrity_detail,
          candidate_diff:$candidate_diff, vigil_handoff:$vigil_handoff,
          attempts:$attempts}'
    else
      printf '%s\n' "─────────────────────────────────────────────────────────"
      printf '%s\n' "  sandbox replay: $REPLAY_OUT_DIR"
      printf '%s\n' "─────────────────────────────────────────────────────────"
      printf '  final:         %s\n' "$_rp_final"
      printf '  attempts:      %s / %s\n' "$_rp_attempts_run" "$_rp_max_attempts"
      printf '  k (pass^k):    %s\n' "$_rp_k"
      printf '\n  per-attempt:\n'
      # Render each attempt: "  attempt N: PASS/FAIL [phase] (flaky?)"
      printf '%s' "$_rp_attempts_json" | jq -r \
        '.[] | "  attempt \(.attempt): \(if .passed then "PASS" else "FAIL" end) [\(.phase // "tests")]\(if .flaky // false then " (flaky)" else "" end)"'
      printf '\n  pass^k report (%s re-runs):\n' "$_rp_k"
      printf '%s' "$_rp_passk_report" | jq -r \
        '.[] | "    attempt \(.attempt): \(.determinism)"'
      printf '  pass^k summary: %s\n' "$_rp_passk_determinism"
      printf '\n'
      if [[ -n "$_rp_candidate_diff" && "$_rp_candidate_diff" != "null" ]]; then
        printf '  candidate diff (NOT applied): %s\n' "$_rp_candidate_diff"
      fi
      if [[ -n "$_rp_vigil_handoff" && "$_rp_vigil_handoff" != "null" ]]; then
        printf '  vigil handoff: %s\n' "$_rp_vigil_handoff"
      fi
      if [[ -f "$REPLAY_OUT_DIR/feedback.json" ]]; then
        printf '  feedback:      %s/feedback.json\n' "$REPLAY_OUT_DIR"
      fi
      if [[ -f "$REPLAY_OUT_DIR/repair-failed-report.md" ]]; then
        printf '  repair-failed: %s/repair-failed-report.md\n' "$REPLAY_OUT_DIR"
      fi
      printf '\n  integrity: '
      case "$_rp_integrity" in
        VERIFIED)     printf 'VERIFIED (sha256)\n' ;;
        MISMATCH)     printf 'MISMATCH — journal tampered since the run\n' ;;
        unverifiable) printf 'unverifiable (%s)\n' "$_rp_integrity_detail" ;;
        *)            printf '%s\n' "$_rp_integrity" ;;
      esac
      printf '%s\n' "─────────────────────────────────────────────────────────"
    fi

    # MISMATCH → exit 4 (tamper detected; callers can detect it).
    # VERIFIED or unverifiable (no envelope) → exit 0.
    [[ "$_rp_tampered" == true ]] && exit 4 || exit 0
    ;;
esac
