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
  # Feed the REAL bats fixture verbatim: the loop's --tests cmd copies it to
  # stdout/stderr and exits 1 so the parser sees the actual runner output.
  run eidolons sandbox loop \
    --tests "cat '$EIDOLONS_ROOT/cli/tests/fixtures/loop-feedback/bats-fail.txt'; exit 1" \
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
  run eidolons sandbox loop \
    --tests "cat '$EIDOLONS_ROOT/cli/tests/fixtures/loop-feedback/pytest-fail.txt'; exit 1" \
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
  run eidolons sandbox loop \
    --tests "cat '$EIDOLONS_ROOT/cli/tests/fixtures/loop-feedback/shellcheck-fail.txt'; exit 1" \
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
  # integrity method must be cksum (bash 3.2 compatible)
  [ "$(jq -r '.integrity.method' .out/loop.json.envelope.json)" = "cksum" ]
  # integrity value must be non-empty
  [ -n "$(jq -r '.integrity.value' .out/loop.json.envelope.json)" ]
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

@test "S1.3: --lint-hook fails → iteration short-circuits, feedback.json phase=lint" {
  _git_project
  # Use the real shellcheck fixture format to verify loci extraction from lint output
  run eidolons sandbox loop \
    --tests 'true' --fix-hook 'true' \
    --lint-hook "cat '$EIDOLONS_ROOT/cli/tests/fixtures/loop-feedback/shellcheck-fail.txt'; exit 1" \
    --max-attempts 1 --allow-unsafe-host --out .out --json
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
