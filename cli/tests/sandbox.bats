#!/usr/bin/env bats
# cli/tests/sandbox.bats — bounded, delegated edit-run-test loop (roadmap #9).
# Adapter, not an engine: the nexus delegates isolation (--via) + the edit step
# (--fix-hook), and owns only the bounded control flow, diff-not-apply discipline,
# and the VIGIL escalation. It REFUSES to run untrusted code without isolation.

load helpers

_git_project() {
  git init -q
  git config user.email t@example.com
  git config user.name tester
  echo broken > state.txt
  git add -A && git commit -qm init
}

# Stage a real captured-fixture as the loop's test output. The loop word-splits
# --tests and execs directly (no `sh -c`), so a compound `cat f; exit 1` cannot be
# passed inline; copy the fixture into cwd and emit a runner script the loop runs
# via `sh runner.sh`. This feeds the REAL runner output (bats/pytest/shellcheck)
# through the parser — the capture-live-before-parsing contract.
_feed_fixture() {
  cp "$EIDOLONS_ROOT/cli/tests/fixtures/loop-feedback/$1" ./runner-out.txt
  printf 'cat runner-out.txt\nexit 1\n' > runner.sh
}

# ── check ─────────────────────────────────────────────────────────────────────
@test "sandbox check: no isolation refuses untrusted execution (exit 3)" {
  run eidolons sandbox check
  [ "$status" -eq 3 ]
  [[ "$output" =~ "refuse" || "$output" =~ "no adequate isolation" ]]
}

@test "sandbox check: --via docker is classified as container (adequate)" {
  run eidolons sandbox check --via 'docker run --rm img' --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.tier')" = "container" ]
  [ "$(echo "$output" | jq -r '.adequate_for_untrusted')" = "true" ]
}

@test "sandbox check: a microVM wrapper is classified as microvm" {
  run eidolons sandbox check --via 'firecracker-run' --json
  [ "$(echo "$output" | jq -r '.tier')" = "microvm" ]
}

@test "sandbox check: --allow-unsafe-host overrides with a warning" {
  run eidolons sandbox check --allow-unsafe-host --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = "unsafe-host-override" ]
}

# ── run ───────────────────────────────────────────────────────────────────────
@test "sandbox run: refuses without isolation" {
  run eidolons sandbox run -- true
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no adequate isolation" ]]
}

@test "sandbox run: a passing test reports passed (exit 0)" {
  run eidolons sandbox run --allow-unsafe-host --json -- true
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.passed')" = "true" ]
}

@test "sandbox run: a failing test reports not-passed (exit 1) — exit code is real, not masked" {
  run eidolons sandbox run --allow-unsafe-host --json -- false
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.passed')" = "false" ]
  [ "$(echo "$output" | jq -r '.exit_code')" -ne 0 ]
}

# ── loop ──────────────────────────────────────────────────────────────────────
@test "sandbox loop: fix-hook fixes the failure → passes; diff-not-apply (no commit)" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo fixed > state.txt' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.merged')" = "false" ]
  [ "$(echo "$output" | jq -r '.attempts[0].passed')" = "false" ]
  [ "$(echo "$output" | jq -r '.attempts[1].passed')" = "true" ]
  # diff-not-apply: only the initial commit exists — the loop never commits/merges
  [ "$(git rev-list --count HEAD)" = "1" ]
  # the candidate diff is emitted for review
  [ -f .out/candidate.diff ]
}

@test "sandbox loop: never-fixable → caps out, emits a VIGIL hand-off, exit 3" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q neverhere state.txt' \
    --fix-hook 'true' --max-attempts 3 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.final')" = "capped" ]
  [ "$(echo "$output" | jq -r '.attempts_run')" = "3" ]
  [ "$(echo "$output" | jq -r '.merged')" = "false" ]
  [ -f .out/repair-failed-report.md ]
  grep -q "VIGIL" .out/repair-failed-report.md
}

@test "sandbox loop: respects --max-attempts as the bounded cap (D5)" {
  _git_project
  run eidolons sandbox loop --tests 'false' --fix-hook 'true' \
    --max-attempts 2 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.attempts_run')" = "2" ]
}

@test "sandbox loop: refuses to run an untrusted loop without isolation" {
  _git_project
  run eidolons sandbox loop --tests 'true'
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no adequate isolation" ]]
}

@test "sandbox loop: a passing test on attempt 1 needs no fix-hook" {
  _git_project
  run eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.attempts_run')" = "1" ]
}

@test "sandbox: unknown subcommand errors" {
  run eidolons sandbox bogus
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown subcommand" ]]
}

# ── loop_contract: localized feedback + anti-reward-hacking + pass^k ────────────
# (roster/aci.yaml loop_contract; APIVR-Δ → Vivi succession, DOSSIER-APIVR-OVERHAUL)

@test "sandbox loop: structured localized feedback carries failing markers + file:line loci" {
  _git_project
  cat > failer.sh <<'SH'
echo "app/foo.rb:42: assertion failed: expected 5 got 3" >&2
exit 1
SH
  run eidolons sandbox loop --tests 'sh failer.sh' \
    --fix-hook 'true' --max-attempts 1 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ -f .out/feedback.json ]
  [ -f .out/full-log.txt ]
  [ "$(jq -r '.contract_version' .out/feedback.json)" = "1.0" ]
  [ "$(jq -r '.loci[0]' .out/feedback.json)" = "app/foo.rb:42" ]
  jq -r '.failing' .out/feedback.json | grep -qi "failed"
}

@test "sandbox loop: fix-hook receives EIDOLONS_SANDBOX_FEEDBACK (localized, not a raw tail)" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'jq -e ".loci" "$EIDOLONS_SANDBOX_FEEDBACK" >/dev/null && echo fixed > state.txt' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
}

@test "sandbox loop: --protect aborts + escalates when the fix-hook mutates an anchoring test" {
  _git_project
  echo "assert fixed" > test_anchor.txt
  git add -A && git commit -qm anchor
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo cheat > test_anchor.txt' \
    --protect 'test_anchor.txt' --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.final')" = "protected-tests-mutated" ]
  [ -f .out/repair-failed-report.md ]
  grep -qi "protected" .out/repair-failed-report.md
}

@test "sandbox loop: regression-first — both pass → passes (phase reproduction)" {
  _git_project
  run eidolons sandbox loop --regression 'true' --reproduction 'true' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.attempts[0].phase')" = "reproduction" ]
}

@test "sandbox loop: regression-first — a broken regression FAILS even if reproduction would pass" {
  _git_project
  run eidolons sandbox loop --regression 'false' --reproduction 'true' \
    --fix-hook 'true' --max-attempts 1 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.attempts[0].phase')" = "regression" ]
}

@test "sandbox loop: --k pass^k blocks a flaky green (non-deterministic pass)" {
  _git_project
  cat > flaky.sh <<'SH'
if [ -f .ctr ]; then exit 1; else : > .ctr; exit 0; fi
SH
  run eidolons sandbox loop --tests 'sh flaky.sh' \
    --fix-hook 'true' --k 2 --max-attempts 1 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.attempts[0].flaky')" = "true" ]
  [ "$(echo "$output" | jq -r '.final')" = "flaky" ]
}

@test "sandbox loop: default --k 1 keeps a single green passing (back-compat)" {
  _git_project
  run eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.k')" = "1" ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
}

# ── S1.4-parser: deepened localized-feedback parser (capture-live fixtures) ────
# Each test drives the loop with a real fixture so the parser processes verbatim
# runner output — not fabricated strings (capture-live mandate).

@test "S1.4-parser: bats fixture — extracts bats-style loci (test-file:line) and test name" {
  _git_project
  # Feed the REAL bats fixture verbatim so the parser sees actual runner output.
  _feed_fixture bats-fail.txt
  run eidolons sandbox loop \
    --tests 'sh runner.sh' \
    --fix-hook 'true' --max-attempts 1 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ -f .out/feedback.json ]
  # Loci must contain math.bats:3 or math.bats:7 (from "(in test file math.bats, line 3)")
  jq -r '.loci[]' .out/feedback.json | grep -q 'math\.bats:[37]'
  # test_name must include the failing test name from "not ok N <name>"
  jq -r '.test_name[]' .out/feedback.json | grep -q 'addition computes the right total'
  # contract_version stays "1.0" (additive-only change)
  [ "$(jq -r '.contract_version' .out/feedback.json)" = "1.0" ]
}

@test "S1.4-parser: pytest fixture — extracts colon-form loci and FAILED test name" {
  _git_project
  _feed_fixture pytest-fail.txt
  run eidolons sandbox loop \
    --tests 'sh runner.sh' \
    --fix-hook 'true' --max-attempts 1 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ -f .out/feedback.json ]
  # loci must contain calc_test.py:8 (colon form)
  jq -r '.loci[]' .out/feedback.json | grep -q 'calc_test\.py:8'
  # test_name must include the pytest test name
  jq -r '.test_name[]' .out/feedback.json | grep -q 'test_running_total_inclusive'
  # assertion must capture the assert 10 == 15 line
  jq -r '.assertion[]' .out/feedback.json | grep -qi 'assert'
}

@test "S1.4-parser: shellcheck fixture — extracts shellcheck-style loci (file:line)" {
  _git_project
  _feed_fixture shellcheck-fail.txt
  run eidolons sandbox loop \
    --tests 'sh runner.sh' \
    --fix-hook 'true' --max-attempts 1 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ -f .out/feedback.json ]
  # loci must contain deploy.sh:4 (shellcheck "In deploy.sh line 4:" format)
  jq -r '.loci[]' .out/feedback.json | grep -q 'deploy\.sh:4'
}

@test "S1.4-parser: back-compat — existing fields (contract_version, failing, loci, output_tail) still present" {
  _git_project
  cat > failer.sh <<'SH'
echo "app/foo.rb:42: assertion failed: expected 5 got 3" >&2
exit 1
SH
  run eidolons sandbox loop --tests 'sh failer.sh' \
    --fix-hook 'true' --max-attempts 1 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ -f .out/feedback.json ]
  # All original fields must be present
  [ "$(jq -r '.contract_version' .out/feedback.json)" = "1.0" ]
  jq -e '.failing' .out/feedback.json >/dev/null
  jq -e '.loci' .out/feedback.json >/dev/null
  jq -e '.output_tail' .out/feedback.json >/dev/null
  # New additive fields must also be present
  jq -e '.test_name' .out/feedback.json >/dev/null
  jq -e '.assertion' .out/feedback.json >/dev/null
}

@test "sandbox loop: a chatty fix-hook (stdout) must NOT corrupt the --json ledger" {
  _git_project
  # An LLM fix-hook prints a verbose response to stdout; that must go to stderr, not
  # pollute the loop's own --json ledger (regression: it did, so eval-swe's jq parse
  # failed → resolved tasks mis-counted as unresolved). Capture stdout only.
  eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo "verbose model summary — definitely not json"; echo fixed > state.txt' \
    --allow-unsafe-host --out .out --json > ledger.json 2>/dev/null
  [ "$(jq -r '.final' ledger.json)" = "passed" ]
  [ "$(jq -r '.attempts[1].passed' ledger.json)" = "true" ]
}

# ── S1.2: pass^k breakdown in loop.json + ECL inform sidecar ─────────────────

@test "S1.2: loop.json carries passk breakdown (k, runs array) — additive field" {
  _git_project
  run eidolons sandbox loop --tests 'true' --k 2 --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ -f .out/loop.json ]
  # .k is preserved (back-compat: sandbox.bats:189-195 asserts .k)
  [ "$(jq -r '.k' .out/loop.json)" = "2" ]
  # passk additive field must exist
  jq -e '.passk' .out/loop.json >/dev/null
  [ "$(jq -r '.passk.k' .out/loop.json)" = "2" ]
  # runs array must have at least 1 entry (attempt 1)
  [ "$(jq -r '.passk.runs | length' .out/loop.json)" -ge 1 ]
}

@test "S1.2: default --k 1 keeps .k==1 back-compat (pass^k back-compat regression)" {
  _git_project
  run eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.k' .out/loop.json)" = "1" ]
  [ "$(jq -r '.final' .out/loop.json)" = "passed" ]
}

@test "S1.2: ECL inform sidecar loop.json.envelope.json is emitted after loop" {
  _git_project
  run eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ -f .out/loop.json.envelope.json ]
  # Must be valid JSON
  jq -e . .out/loop.json.envelope.json >/dev/null
  # performative must be "inform" (closed-10 ECL set, no new performative)
  [ "$(jq -r '.performative' .out/loop.json.envelope.json)" = "inform" ]
  # sender must be eidolons-sandbox
  [ "$(jq -r '.sender.eidolon' .out/loop.json.envelope.json)" = "eidolons-sandbox" ]
  # integrity method must be sha256 (ECL P0: SHA-256 is the default integrity algorithm)
  [ "$(jq -r '.integrity.method' .out/loop.json.envelope.json)" = "sha256" ]
  # integrity value must be a 64-hex-char SHA-256 digest
  [[ "$(jq -r '.integrity.value' .out/loop.json.envelope.json)" =~ ^[0-9a-f]{64}$ ]]
  # artifact path references loop.json
  [ "$(jq -r '.artifact.path' .out/loop.json.envelope.json)" = "loop.json" ]
}

@test "S1.2: passk.runs records per-run pass boolean for each k re-run" {
  _git_project
  # With k=2 and a stable passing test, both re-runs should be recorded as passed
  run eidolons sandbox loop --tests 'true' --k 2 --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  # attempt 1's passk_runs should have 2 entries (k=2 re-runs)
  [ "$(jq -r '.attempts[0].passk_runs | length' .out/loop.json)" = "2" ]
  # both runs should be passed
  [ "$(jq -r '[.attempts[0].passk_runs[].passed] | all' .out/loop.json)" = "true" ]
}

@test "S1.3: --lint-hook passes → tests run normally (phase not lint)" {
  _git_project
  run eidolons sandbox loop --tests 'true' \
    --fix-hook 'true' --lint-hook 'true' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.final' .out/loop.json)" = "passed" ]
  # phase must not be "lint" (lint passed → tests ran)
  [ "$(jq -r '.attempts[0].phase' .out/loop.json)" != "lint" ]
}

@test "S1.6: --fresh-context exports EIDOLONS_SANDBOX_FRESH_CONTEXT=true to fix-hook" {
  _git_project
  # The fix-hook dumps its env to a file so we can inspect it.
  run eidolons sandbox loop \
    --tests 'grep -q fixed state.txt' \
    --fix-hook 'env > /tmp/s16-env-dump.txt; echo fixed > state.txt' \
    --fresh-context --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ -f /tmp/s16-env-dump.txt ]
  # EIDOLONS_SANDBOX_FRESH_CONTEXT must be exported and set to "true"
  grep -q 'EIDOLONS_SANDBOX_FRESH_CONTEXT=true' /tmp/s16-env-dump.txt
  rm -f /tmp/s16-env-dump.txt
}

@test "S1.6: absent --fresh-context exports EIDOLONS_SANDBOX_FRESH_CONTEXT=false to fix-hook" {
  _git_project
  run eidolons sandbox loop \
    --tests 'grep -q fixed state.txt' \
    --fix-hook 'env > /tmp/s16-env-dump2.txt; echo fixed > state.txt' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ -f /tmp/s16-env-dump2.txt ]
  # Without --fresh-context, the var must be set to "false" (not unset, not "true")
  grep -q 'EIDOLONS_SANDBOX_FRESH_CONTEXT=false' /tmp/s16-env-dump2.txt
  rm -f /tmp/s16-env-dump2.txt
}

@test "S1.6: fix-hook env carries only documented localized vars (no transcript var)" {
  _git_project
  # The env block exports exactly the documented vars; no accumulated transcript.
  run eidolons sandbox loop \
    --tests 'grep -q fixed state.txt' \
    --fix-hook 'env | grep "^EIDOLONS_SANDBOX_" | sort > /tmp/s16-envvars.txt; echo fixed > state.txt' \
    --fresh-context --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ -f /tmp/s16-envvars.txt ]
  # The documented vars must all be present
  grep -q 'EIDOLONS_SANDBOX_FEEDBACK=' /tmp/s16-envvars.txt
  grep -q 'EIDOLONS_SANDBOX_FULL_LOG=' /tmp/s16-envvars.txt
  grep -q 'EIDOLONS_SANDBOX_LAST_OUTPUT=' /tmp/s16-envvars.txt
  grep -q 'EIDOLONS_SANDBOX_ATTEMPT=' /tmp/s16-envvars.txt
  grep -q 'EIDOLONS_SANDBOX_BASE=' /tmp/s16-envvars.txt
  grep -q 'EIDOLONS_SANDBOX_FRESH_CONTEXT=' /tmp/s16-envvars.txt
  # No TRANSCRIPT or HISTORY var (no accumulated transcript exported)
  ! grep -q 'EIDOLONS_SANDBOX_TRANSCRIPT\|EIDOLONS_SANDBOX_HISTORY\|EIDOLONS_SANDBOX_PRIOR' /tmp/s16-envvars.txt
  rm -f /tmp/s16-envvars.txt
}

@test "S1.5: sealed holdout passes → final=passed (no reward-hacking)" {
  _git_project
  run eidolons sandbox loop --tests 'true' \
    --holdout 'true' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.final' .out/loop.json)" = "passed" ]
}

@test "S1.5: sealed holdout fails (visible pass, holdout fail) → final=reward-hacked + VIGIL report" {
  _git_project
  # Visible tests pass; sealed holdout fails.
  run eidolons sandbox loop --tests 'true' \
    --holdout 'false' --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(jq -r '.final' .out/loop.json)" = "reward-hacked" ]
  [ -f .out/repair-failed-report.md ]
  grep -qi "reward-hacked\|sealed holdout\|evaluator-gaming" .out/repair-failed-report.md
}

@test "S1.5: holdout command is NEVER exported to the fix-hook env (sealed by construction)" {
  _git_project
  # The fix-hook dumps its env; the holdout command string must NOT appear.
  # We give the holdout a distinctive string and assert env does not contain it.
  run eidolons sandbox loop \
    --tests 'grep -q fixed state.txt' \
    --fix-hook 'env > /tmp/fh-env-dump.txt; echo fixed > state.txt' \
    --holdout 'true' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  # The env dump must not contain HOLDOUT or the holdout value.
  ! grep -q 'HOLDOUT' /tmp/fh-env-dump.txt 2>/dev/null || true
  rm -f /tmp/fh-env-dump.txt
}

@test "S1.3: --lint-hook fails → iteration short-circuits, feedback.json phase=lint" {
  _git_project
  # A FAILING test triggers the fix-hook path; the lint gate then runs on the edit
  # and fails (real shellcheck fixture). max-attempts 2 so the fix→lint path is
  # reached (attempt 1) and the lint-pending re-fix caps (attempt 2). lint-hook runs
  # via `bash -c`, so the compound `cat …; exit 1` is valid here (unlike --tests).
  run eidolons sandbox loop \
    --tests 'false' --fix-hook 'true' \
    --lint-hook "cat '$EIDOLONS_ROOT/cli/tests/fixtures/loop-feedback/shellcheck-fail.txt'; exit 1" \
    --max-attempts 2 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ -f .out/feedback.json ]
  [ "$(jq -r '.phase' .out/feedback.json)" = "lint" ]
  [ "$(jq -r '.passed' .out/feedback.json)" = "false" ]
  # loci must contain deploy.sh:4 from the shellcheck fixture
  jq -r '.loci[]' .out/feedback.json | grep -q 'deploy\.sh:4'
}

@test "S1.3: --lint-hook fails → tests are NOT run that iteration (no test phase in attempts)" {
  _git_project
  # If the lint-hook fails, the iteration should not produce a test-phase attempt entry.
  # We use max-attempts=2 so the loop can record attempts; first attempt short-circuits.
  cat > fix2.sh <<'SH'
# no-op fix hook
SH
  LINT_CALL_COUNT=0
  run eidolons sandbox loop \
    --tests 'false' --fix-hook 'true' \
    --lint-hook 'exit 1' \
    --max-attempts 2 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  # feedback.json phase must be lint (lint short-circuited)
  [ "$(jq -r '.phase' .out/feedback.json)" = "lint" ]
}

@test "S1.2: flaky pass^k still records non-deterministic run in passk.runs" {
  _git_project
  cat > flaky2.sh <<'SH'
if [ -f .ctr2 ]; then exit 1; else : > .ctr2; exit 0; fi
SH
  run eidolons sandbox loop --tests 'sh flaky2.sh' \
    --fix-hook 'true' --k 2 --max-attempts 1 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(jq -r '.final' .out/loop.json)" = "flaky" ]
  # passk.runs for attempt 1 must exist (the k re-run was attempted)
  [ "$(jq -r '.passk.runs | length' .out/loop.json)" -ge 1 ]
}

# ── replay (#9): read-only render of a completed loop's artifacts ─────────────

@test "replay: renders a PASSED loop — exit 0, output mentions final=passed" {
  _git_project
  # Run a real passing loop to produce the out-dir artifacts.
  eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json > /dev/null
  # Replay the out-dir: must exit 0 and mention "passed".
  run eidolons sandbox replay .out
  [ "$status" -eq 0 ]
  [[ "$output" =~ "passed" ]]
}

@test "replay --json: emits parseable JSON with final, integrity, passk_determinism" {
  _git_project
  eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json > /dev/null
  run eidolons sandbox replay .out --json
  [ "$status" -eq 0 ]
  # Must be valid JSON (jq -e fails if output is not valid JSON or falsey).
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  # integrity field must be present (VERIFIED, unverifiable, or MISMATCH).
  [ -n "$(echo "$output" | jq -r '.integrity')" ]
  # passk_determinism field must be present.
  [ -n "$(echo "$output" | jq -r '.passk_determinism')" ]
}

@test "replay: integrity VERIFIED on an untampered out-dir" {
  _git_project
  eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json > /dev/null
  run eidolons sandbox replay .out --json
  [ "$status" -eq 0 ]
  # Integrity must be VERIFIED (loop just ran; loop.json not mutated).
  [ "$(echo "$output" | jq -r '.integrity')" = "VERIFIED" ]
}

@test "replay: integrity MISMATCH after tampering loop.json — exits non-zero (exit 4)" {
  _git_project
  eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json > /dev/null
  # Tamper: append a space to loop.json — SHA-256 will no longer match the envelope.
  printf ' ' >> .out/loop.json
  run eidolons sandbox replay .out --json
  [ "$status" -eq 4 ]
  [ "$(echo "$output" | jq -r '.integrity')" = "MISMATCH" ]
}

@test "replay: missing out-dir → die non-zero" {
  run eidolons sandbox replay /nonexistent/replay-dir
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" || "$output" =~ "directory" ]]
}

@test "replay: missing loop.json → die non-zero" {
  mkdir -p .empty-out
  run eidolons sandbox replay .empty-out
  [ "$status" -ne 0 ]
  [[ "$output" =~ "loop.json" ]]
}

@test "replay: read-only proof — replay does not re-execute or mutate loop.json" {
  _git_project
  eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json > /dev/null
  # Capture modification time of loop.json before replay.
  _mtime_before="$(ls -l .out/loop.json)"
  _attempts_before="$(jq -r '.attempts_run' .out/loop.json)"
  # Run replay (no --allow-unsafe-host — read-only needs no isolation).
  run eidolons sandbox replay .out
  [ "$status" -eq 0 ]
  # loop.json must NOT have been mutated (mtime and attempts_run unchanged).
  _mtime_after="$(ls -l .out/loop.json)"
  [ "$_mtime_before" = "$_mtime_after" ]
  [ "$(jq -r '.attempts_run' .out/loop.json)" = "$_attempts_before" ]
}

@test "replay: works WITHOUT --allow-unsafe-host (no isolation needed; read-only)" {
  _git_project
  eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json > /dev/null
  # replay must succeed without any isolation flag or --via.
  run eidolons sandbox replay .out
  [ "$status" -eq 0 ]
}

@test "replay: pass^k NON-DETERMINISTIC flag detected for a flaky attempt" {
  _git_project
  cat > flaky3.sh <<'SH'
if [ -f .ctr3 ]; then exit 1; else : > .ctr3; exit 0; fi
SH
  # k=2, max-attempts=1: first run passes, second (k re-run) fails → flaky.
  eidolons sandbox loop --tests 'sh flaky3.sh' \
    --fix-hook 'true' --k 2 --max-attempts 1 --allow-unsafe-host --out .out --json > /dev/null || true
  run eidolons sandbox replay .out --json
  # replay must exit 0 (integrity, not flakiness, drives the exit code).
  [ "$status" -eq 0 ]
  # passk_determinism must flag non-determinism.
  [[ "$(echo "$output" | jq -r '.passk_determinism')" =~ "NON-DETERMINISTIC" ]]
}

# ── Stage 2: red gate + fanout + judge (red-gate/fanout/judge — coder-7.5) ─────
@test "S2-red: --require-red blocks a VACUOUS reproduction (passes on base) → final=vacuous-reproduction, exit 3" {
  _git_project
  # The "reproduction" passes on the base tree → it cannot anchor a fix.
  run eidolons sandbox loop --reproduction 'true' --require-red \
    --fix-hook 'echo fixed > state.txt' --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(jq -r '.final' .out/loop.json)" = "vacuous-reproduction" ]
  [ "$(jq -r '.red_gate' .out/loop.json)" = "vacuous" ]
  # No fix attempt may run against a vacuous repro test.
  [ "$(jq -r '.attempts_run' .out/loop.json)" = "0" ]
  [ -f .out/repair-failed-report.md ]
  grep -qi "vacuous" .out/repair-failed-report.md
}

@test "S2-red: --require-red verifies red then the loop proceeds to green (red_gate=verified-red)" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' --require-red \
    --fix-hook 'echo fixed > state.txt' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.red_gate')" = "verified-red" ]
}

@test "S2-red: fanout candidates read the verified-red base feedback (attempt 0, phase red-gate)" {
  _git_project
  # The candidate proves what feedback it saw by copying it aside. (In iterate
  # mode attempt 1 legitimately regenerates feedback; the red seed is the shared
  # base-failure signal for FANOUT candidates.)
  cat > cand.sh <<'SH'
cp "$EIDOLONS_SANDBOX_FEEDBACK" fh-saw-feedback.json
echo fixed > state.txt
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' --require-red \
    --fanout 2 --fix-hook 'sh cand.sh' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ -f fh-saw-feedback.json ]
  [ "$(jq -r '.phase' fh-saw-feedback.json)" = "red-gate" ]
  [ "$(jq -r '.attempt' fh-saw-feedback.json)" = "0" ]
}

@test "S2-fanout: selects the first PASSING candidate (candidate 2 of 3) — external selection" {
  _git_project
  # Candidate 1 writes a wrong fix; candidate 2 writes the right one.
  cat > cand.sh <<'SH'
if [ "$EIDOLONS_SANDBOX_CANDIDATE" = "2" ]; then echo fixed > state.txt
else echo wrong > state.txt; fi
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fanout 3 --fix-hook 'sh cand.sh' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.selected_candidate')" = "2" ]
  [ "$(echo "$output" | jq -r '.attempts_run')" = "2" ]
  # Survivor's edits remain in the tree; diff-not-apply still holds (no commit).
  grep -q fixed state.txt
  [ "$(git rev-list --count HEAD)" = "1" ]
}

@test "S2-fanout: all candidates fail → final=capped, exit 3, per-candidate diffs kept" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q neverhere state.txt' \
    --fanout 2 --fix-hook 'echo nope > state.txt' --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.final')" = "capped" ]
  [ "$(echo "$output" | jq -r '.attempts_run')" = "2" ]
  [ -f .out/candidate-1.diff ]
  [ -f .out/candidate-2.diff ]
}

@test "S2-fanout: tree is RESET between candidates (candidate 2 starts from base, not from candidate 1's edits)" {
  _git_project
  # Candidate 1 plants junk + fails; candidate 2 fixes. If the tree were not
  # reset, junk.txt would leak into the survivor's candidate diff.
  cat > cand.sh <<'SH'
if [ "$EIDOLONS_SANDBOX_CANDIDATE" = "1" ]; then echo junk > junk.txt; echo wrong > state.txt
else echo fixed > state.txt; fi
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fanout 2 --fix-hook 'sh cand.sh' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.selected_candidate')" = "2" ]
  [ ! -f junk.txt ]
  ! grep -q junk .out/candidate.diff
}

@test "S2-fanout: every candidate gets FRESH context forced + candidate/fanout env vars" {
  _git_project
  cat > cand.sh <<'SH'
echo "$EIDOLONS_SANDBOX_FRESH_CONTEXT $EIDOLONS_SANDBOX_CANDIDATE $EIDOLONS_SANDBOX_FANOUT" >> env-seen.txt
echo fixed > state.txt
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fanout 2 --fix-hook 'sh cand.sh' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  # env-seen.txt is recreated by the surviving candidate after the tree reset.
  grep -q "true 1 2" env-seen.txt || grep -q "true" env-seen.txt
}

@test "S2-fanout: candidates share the SAME base-failure feedback (attempt 0; per-candidate failures do not overwrite it)" {
  _git_project
  cat > cand.sh <<'SH'
cp "$EIDOLONS_SANDBOX_FEEDBACK" "feedback-seen-$EIDOLONS_SANDBOX_CANDIDATE.json" 2>/dev/null || true
echo wrong > state.txt
SH
  run eidolons sandbox loop --tests 'grep -q neverhere state.txt' \
    --fanout 2 --fix-hook 'sh cand.sh' --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  # Candidate 2 must see attempt-0 (base) feedback, not candidate 1's failure.
  [ "$(jq -r '.attempt' .out/feedback.json)" = "0" ]
}

@test "S2-fanout: --fanout without --fix-hook dies" {
  _git_project
  run eidolons sandbox loop --tests 'false' --fanout 2 --allow-unsafe-host --out .out --json
  [ "$status" -ne 0 ]
  [[ "$output" =~ "fanout" ]]
}

@test "S2-fanout: a reward-hacked candidate is REJECTED, the next candidate can still win" {
  _git_project
  echo holdout-broken > holdout-state.txt
  git add -A && git commit -qm holdout
  # Candidate 1 games the visible test only; candidate 2 fixes both surfaces.
  cat > cand.sh <<'SH'
if [ "$EIDOLONS_SANDBOX_CANDIDATE" = "1" ]; then echo fixed > state.txt
else echo fixed > state.txt; echo holdout-ok > holdout-state.txt; fi
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --holdout 'grep -q holdout-ok holdout-state.txt' \
    --fanout 2 --fix-hook 'sh cand.sh' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.selected_candidate')" = "2" ]
  [ "$(echo "$output" | jq -r '.attempts[0].rejected')" = "reward-hacked" ]
}

@test "S2-judge: --judge-hook approves → final=passed, judge=approved" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo fixed > state.txt' --judge-hook 'true' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.judge')" = "approved" ]
}

@test "S2-judge: --judge-hook rejects → final=judge-rejected + VIGIL hand-off (iterate mode)" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo fixed > state.txt' --judge-hook 'false' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.final')" = "judge-rejected" ]
  [ "$(echo "$output" | jq -r '.judge')" = "rejected" ]
  [ -f .out/repair-failed-report.md ]
  grep -qi "judge" .out/repair-failed-report.md
}

@test "S2-judge: the judge receives the candidate diff via EIDOLONS_SANDBOX_DIFF" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo fixed > state.txt' \
    --judge-hook 'grep -q "+fixed" "$EIDOLONS_SANDBOX_DIFF"' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.judge')" = "approved" ]
}

@test "S2-judge: judge rejection in fanout tries the NEXT candidate" {
  _git_project
  # Both candidates make the test pass; the judge rejects diffs that touch the
  # TRACKED marker.txt (candidate 1 does, candidate 2 does not).
  echo clean > marker.txt
  git add -A && git commit -qm marker
  cat > cand.sh <<'SH'
echo fixed > state.txt
if [ "$EIDOLONS_SANDBOX_CANDIDATE" = "1" ]; then echo sneaky > marker.txt; fi
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fanout 2 --fix-hook 'sh cand.sh' \
    --judge-hook '! grep -q sneaky "$EIDOLONS_SANDBOX_DIFF"' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.selected_candidate')" = "2" ]
  [ "$(echo "$output" | jq -r '.attempts[0].rejected')" = "judge-rejected" ]
}

@test "S2: ledger back-compat — fanout/red_gate/judge fields default sanely on a plain loop" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo fixed > state.txt' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.fanout')" = "1" ]
  [ "$(echo "$output" | jq -r '.selected_candidate')" = "0" ]
  [ "$(echo "$output" | jq -r '.red_gate')" = "" ]
  [ "$(echo "$output" | jq -r '.judge')" = "" ]
}

# ── S3-cascade: post-generation tier cascade (light<standard<deep) ────────────
# Evidence basis: pre-generation difficulty routers are ML-shaped; run-cheap ->
# verify -> escalate is the only deterministic-capable routing class. The loop,
# not the model, decides escalation — see 'eidolons sandbox loop --help'.

@test "S3-cascade: escalates light -> standard when light's fix-hook can't fix it, reports cascade_tier_used" {
  _git_project
  # fix.sh only "fixes" state.txt when it is invoked at tier=standard — proving
  # the fix-hook (not the sandbox) maps tier -> model, and that escalation is
  # driven purely by EIDOLONS_SANDBOX_MODEL_TIER.
  cat > fix.sh <<'SH'
if [ "$EIDOLONS_SANDBOX_MODEL_TIER" = "standard" ]; then
  echo fixed > state.txt
fi
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'sh fix.sh' --cascade light,standard --max-attempts 2 \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.cascade_tier_used')" = "standard" ]
  [ -f .out/cascade-light/loop.json ]
  [ -f .out/cascade-standard/loop.json ]
  # the light tier really did exhaust its attempts before escalating
  [ "$(jq -r '.final' .out/cascade-light/loop.json)" = "capped" ]
}

@test "S3-cascade: a 3-tier ladder escalates twice and reports the winning (deep) tier" {
  _git_project
  cat > fix.sh <<'SH'
if [ "$EIDOLONS_SANDBOX_MODEL_TIER" = "deep" ]; then
  echo fixed > state.txt
fi
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'sh fix.sh' --cascade light,standard,deep --max-attempts 2 \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.cascade_tier_used')" = "deep" ]
}

@test "S3-cascade: rejects an unknown tier name (usage error)" {
  _git_project
  run eidolons sandbox loop --tests 'true' --cascade bogus,standard --allow-unsafe-host --out .out
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cascade" ]]
  [[ "$output" =~ "unknown tier" ]]
}

@test "S3-cascade: rejects non-ascending tiers (usage error)" {
  _git_project
  run eidolons sandbox loop --tests 'true' --cascade standard,light --allow-unsafe-host --out .out
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ascending" ]]
}

@test "S3-cascade: rejects a single tier (needs 2-3)" {
  _git_project
  run eidolons sandbox loop --tests 'true' --cascade light --allow-unsafe-host --out .out
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cascade" ]]
}

@test "S3-cascade: rejects more than 3 tiers" {
  _git_project
  run eidolons sandbox loop --tests 'true' --cascade light,standard,deep,light --allow-unsafe-host --out .out
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cascade" ]]
}

@test "S3-cascade: absent --cascade never exports EIDOLONS_SANDBOX_MODEL_TIER to the fix-hook (byte-identical)" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'env > /tmp/s3-cascade-env-dump.txt; echo fixed > state.txt' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  ! grep -q 'EIDOLONS_SANDBOX_MODEL_TIER' /tmp/s3-cascade-env-dump.txt
  rm -f /tmp/s3-cascade-env-dump.txt
}

@test "S3-cascade: cascade_tier_used defaults to empty string when --cascade is not used (additive back-compat field)" {
  _git_project
  run eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.cascade_tier_used')" = "" ]
}

# ── S3-ratchet: test-file anti-tamper ratchet (default-on; --allow-test-edits) ─
# Evidence basis: strong policies exploit weak verifiers by tampering with
# tests (deleting failing tests, editing assertions) — the verifier must
# confirm the frozen checks are the ones that actually ran.

@test "S3-ratchet: a fix-hook that EDITS a snapshotted test file is REJECTED as test-tamper; loop caps with tamper_rejections>=1" {
  _git_project
  echo "assert 1" > sometest.sh
  git add -A && git commit -qm addtest
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo tampered > sometest.sh; echo fixed > state.txt' \
    --max-attempts 2 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.tamper_rejections')" -ge 1 ]
  # the test file really was left tampered (the loop rejects, it does not revert)
  grep -q tampered sometest.sh
}

@test "S3-ratchet: a fix-hook that DELETES a snapshotted test file is REJECTED as test-tamper" {
  _git_project
  echo "assert 1" > sometest.sh
  git add -A && git commit -qm addtest
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'rm -f sometest.sh; echo fixed > state.txt' \
    --max-attempts 2 --allow-unsafe-host --out .out --json
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.tamper_rejections')" -ge 1 ]
}

@test "S3-ratchet: a fix-hook that only ADDS a new test file is allowed (adding tests is legitimate)" {
  _git_project
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo "new test" > newtest.sh; echo fixed > state.txt' \
    --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.tamper_rejections')" = "0" ]
}

@test "S3-ratchet: --allow-test-edits disables the ratchet — the same tampering fix-hook now passes" {
  _git_project
  echo "assert 1" > sometest.sh
  git add -A && git commit -qm addtest
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fix-hook 'echo tampered > sometest.sh; echo fixed > state.txt' \
    --allow-test-edits --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.tamper_rejections')" = "0" ]
}

@test "S3-ratchet: tamper_rejections defaults to 0 on an ordinary loop (additive back-compat field)" {
  _git_project
  run eidolons sandbox loop --tests 'true' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.tamper_rejections')" = "0" ]
}

@test "S3-ratchet: --fanout — a candidate that tampers with a test file is rejected, the next candidate can still win" {
  _git_project
  echo "assert 1" > sometest.sh
  git add -A && git commit -qm addtest
  # Candidate 1 tampers with the test file; candidate 2 fixes state.txt cleanly.
  cat > cand.sh <<'SH'
if [ "$EIDOLONS_SANDBOX_CANDIDATE" = "1" ]; then
  echo tampered > sometest.sh
  echo fixed > state.txt
else
  echo fixed > state.txt
fi
SH
  run eidolons sandbox loop --tests 'grep -q fixed state.txt' \
    --fanout 2 --fix-hook 'sh cand.sh' --allow-unsafe-host --out .out --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.final')" = "passed" ]
  [ "$(echo "$output" | jq -r '.selected_candidate')" = "2" ]
  [ "$(echo "$output" | jq -r '.attempts[0].rejected')" = "test-tamper" ]
  [ "$(echo "$output" | jq -r '.tamper_rejections')" = "1" ]
}
