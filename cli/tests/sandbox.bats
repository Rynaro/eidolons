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
