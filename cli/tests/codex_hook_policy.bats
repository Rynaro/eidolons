#!/usr/bin/env bats
# Issue #640: documented Codex hook groups and observable routing failures.
load helpers

_hook_fixture() {
  local policy="${1:-fail-open}"
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire: [codex]
members:
  - name: atlas
    version: "^1.0.0"
harness:
  hook_failure_policy: $policy
EOF
  seed_lock
  eidolons harness install --hosts codex --non-interactive >/dev/null 2>&1
  SHIM=".eidolons/harness/hooks/codex-UserPromptSubmit.sh"
  export SHIM
  mkdir -p "$BATS_TEST_TMPDIR/fake-bin"
  cat > "$BATS_TEST_TMPDIR/fake-bin/eidolons" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_HOOK_MODE:-error}" in
  error) exit 7 ;;
  empty) exit 0 ;;
  invalid) printf 'not-json\n' ;;
  valid) printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"route to ATLAS"}}\n' ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-bin/eidolons"
  export PATH="$BATS_TEST_TMPDIR/fake-bin:$PATH"
}

@test "issue 640: Codex hooks have matcher groups and command handlers" {
  _hook_fixture
  jq -e '
    ([.hooks.UserPromptSubmit[]?.hooks[]? | select(.type == "command" and (.command | endswith("codex-UserPromptSubmit.sh")))] | length == 1) and
    ([.hooks.SessionStart[]? | select(.matcher == "startup|resume|clear|compact") | .hooks[]? | select(.type == "command")] | length == 1)
  ' .codex/hooks.json >/dev/null
}

@test "issue 640: Codex hook install migrates own flat entries and preserves foreign groups" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
members:
  - name: atlas
    version: "^1.0.0"
EOF
  seed_lock
  mkdir -p .codex
  cat > .codex/hooks.json <<'EOF'
{"hooks":{"UserPromptSubmit":[{"command":".eidolons/harness/hooks/codex-UserPromptSubmit.sh"},{"hooks":[{"type":"command","command":"user-foreign"}]}]}}
EOF
  eidolons harness install --hosts codex --non-interactive >/dev/null 2>&1
  jq -e '
    ([.hooks.UserPromptSubmit[] | select(.command? == ".eidolons/harness/hooks/codex-UserPromptSubmit.sh")] | length == 0) and
    ([.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == "user-foreign")] | length == 1) and
    ([.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == ".eidolons/harness/hooks/codex-UserPromptSubmit.sh")] | length == 1)
  ' .codex/hooks.json >/dev/null
}

@test "issue 640: fail-open records qualified kernel error without blocking" {
  _hook_fixture fail-open
  export FAKE_HOOK_MODE=error
  run bash -c 'printf "{\"prompt\":\"fix the secret-needle bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  jq -e '.reason == "kernel-error" and .policy == "fail-open"' .eidolons/harness/hook-failures.jsonl >/dev/null
  ! grep -q 'secret-needle' .eidolons/harness/hook-failures.jsonl
}

@test "issue 640: warn emits diagnostic for empty qualified routing output" {
  _hook_fixture warn
  export FAKE_HOOK_MODE=empty
  run bash -c 'printf "{\"prompt\":\"fix the bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("empty-or-invalid-output")' >/dev/null
}

@test "issue 640: warn reports kernel nonzero without blocking" {
  _hook_fixture warn
  export FAKE_HOOK_MODE=error
  run bash -c 'printf "{\"prompt\":\"fix the bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("kernel-error")' >/dev/null
}

@test "issue 640: fail-closed blocks kernel nonzero" {
  _hook_fixture fail-closed
  export FAKE_HOOK_MODE=error
  run bash -c 'printf "{\"prompt\":\"fix the bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.continue == false and (.stopReason | contains("kernel-error"))' >/dev/null
}

@test "issue 640: fail-closed blocks empty output for an unlisted work verb" {
  _hook_fixture fail-closed
  export FAKE_HOOK_MODE=empty
  run bash -c 'printf "{\"prompt\":\"Please solve the bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.continue == false and (.stopReason | contains("empty-or-invalid-output"))' >/dev/null
}

@test "issue 640: fail-closed missing CLI still emits blocking JSON without jq" {
  _hook_fixture fail-closed
  local jq_path
  jq_path="$(command -v jq)"
  rm "$BATS_TEST_TMPDIR/fake-bin/eidolons"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/no-home"
  export PATH="/usr/bin:/bin"
  run bash -c 'printf "{\"prompt\":\"Please solve the bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | "$jq_path" -e '.continue == false and (.stopReason | contains("missing-cli"))' >/dev/null
}

@test "issue 640: malformed manifest aborts hook install before writing shims" {
  cat > eidolons.yaml <<'EOF'
version: [not: valid: yaml
EOF
  run eidolons harness install --hosts codex --non-interactive
  [ "$status" -ne 0 ]
  [ ! -e .eidolons/harness/hooks/codex-UserPromptSubmit.sh ]
}

@test "issue 640: missing CLI yields a bounded failure receipt" {
  _hook_fixture fail-open
  ln -s "$(command -v jq)" "$BATS_TEST_TMPDIR/fake-bin/jq"
  rm "$BATS_TEST_TMPDIR/fake-bin/eidolons"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/no-home"
  export PATH="/usr/bin:/bin:$BATS_TEST_TMPDIR/fake-bin"
  run bash -c 'printf "{\"prompt\":\"fix the bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  jq -e '.reason == "missing-cli"' .eidolons/harness/hook-failures.jsonl >/dev/null
}

@test "issue 640: fail-closed blocks malformed input with documented common fields" {
  _hook_fixture fail-closed
  run bash -c 'printf "not-json" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.continue == false and (.stopReason | contains("malformed-input"))' >/dev/null
}

@test "issue 640: fail-closed blocks invalid kernel output" {
  _hook_fixture fail-closed
  export FAKE_HOOK_MODE=invalid
  run bash -c 'printf "{\"prompt\":\"fix the bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.continue == false and (.stopReason | contains("empty-or-invalid-output"))' >/dev/null
}

@test "issue 640: fail-closed treats any nonempty ordinary prompt as requiring a valid response" {
  _hook_fixture fail-closed
  export FAKE_HOOK_MODE=empty
  run bash -c 'printf "{\"prompt\":\"thanks\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.continue == false and (.stopReason | contains("empty-or-invalid-output"))' >/dev/null
  jq -e '.reason == "empty-or-invalid-output" and .policy == "fail-closed"' .eidolons/harness/hook-failures.jsonl >/dev/null
}

@test "issue 640: valid hook output passes unchanged" {
  _hook_fixture fail-closed
  export FAKE_HOOK_MODE=valid
  run bash -c 'printf "{\"prompt\":\"fix the bug\"}" | bash "$SHIM"'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext == "route to ATLAS"' >/dev/null
}

@test "issue 640: harness local smoke invokes real routing kernel without model" {
  _hook_fixture fail-closed
  mkdir -p .eidolons/cortex
  cp "$EIDOLONS_ROOT/EIDOLONS.md" .eidolons/cortex/EIDOLONS.md
  run eidolons harness check --smoke --host codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"harness local smoke: ok"* ]]
  [[ "$output" == *"runtime qualification: unknown"* ]]
}

@test "issue 640: explicit malformed hook policy fails before shim install" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
members:
  - name: atlas
    version: "^1.0.0"
harness:
  hook_failure_policy: null
EOF
  seed_lock
  run eidolons harness install --hosts codex --non-interactive
  [ "$status" -ne 0 ]
  [ ! -f .codex/hooks.json ]
}
