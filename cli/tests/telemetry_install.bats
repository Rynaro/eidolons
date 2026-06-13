#!/usr/bin/env bats
#
# cli/tests/telemetry_install.bats — Phase F install wiring acceptance tests
#
# AC-F5-1  enable writes shim + registers Stop in settings.json
# AC-F5-2  idempotency: enable twice → settings.json byte-identical (jq -cS)
# AC-F5-3  coexistence: UPS/SessionStart hooks untouched by enable
# AC-F5-4  disable removes Stop shim + settings entry + lock entry; leaves others
# AC-F5-5  end-to-end: shim invocation captures an audited row in the store
# AC-F5-6  no-claude-code host: enable exits 0 with honest message, no shim
#
# Billing safety: zero live model calls. Fixture transcript only.
# No NO_LIVE kill-switch required (no claude -p driver anywhere).

load helpers

HARNESS_SHIM_DIR=".eidolons/harness/hooks"

# ─── Setup ────────────────────────────────────────────────────────────────────

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"

  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  # Minimal eidolons.yaml and lock so enable can update the lock.
  seed_manifest
  seed_lock
}

teardown() {
  cd "$EIDOLONS_ROOT"
}

# Fixture transcript path.
FIXTURE_TRANSCRIPT="$EIDOLONS_ROOT/cli/tests/fixtures/telemetry/cc-transcript.jsonl"

# ─── AC-F5-6: no .claude/ → exit 0, honest message, no shim ──────────────────

@test "telemetry enable: no .claude/ dir → exit 0, honest message, no shim written" {
  # No .claude/ directory in the test project.
  run eidolons telemetry enable
  [ "$status" -eq 0 ]
  # Must print an honest message about CC-only MLP scope.
  [[ "$output" =~ "no claude-code host detected" ]] || \
    [[ "$output" =~ "no .claude" ]] || \
    [[ "$output" =~ "CC-audited" ]] || \
    [[ "$output" =~ "other hosts" ]]
  # No shim must have been written.
  [ ! -f "$HARNESS_SHIM_DIR/claude-code-Stop.sh" ]
}

# ─── AC-F5-1: enable writes shim + registers Stop hook ───────────────────────

@test "telemetry enable: writes zero-logic Stop shim to HARNESS_SHIM_DIR" {
  mkdir -p .claude
  run eidolons telemetry enable
  [ "$status" -eq 0 ]
  [ -f "$HARNESS_SHIM_DIR/claude-code-Stop.sh" ]
}

@test "telemetry enable: Stop shim contains 'cat' stdin pipe (zero-logic)" {
  mkdir -p .claude
  eidolons telemetry enable
  grep -q 'cat' "$HARNESS_SHIM_DIR/claude-code-Stop.sh"
}

@test "telemetry enable: Stop shim exec-calls telemetry capture --hook STOP_claude-code --stdin" {
  mkdir -p .claude
  eidolons telemetry enable
  grep -q 'telemetry capture --hook STOP_claude-code --stdin' \
    "$HARNESS_SHIM_DIR/claude-code-Stop.sh"
}

@test "telemetry enable: Stop shim contains NO jq/parsing logic" {
  mkdir -p .claude
  eidolons telemetry enable
  # The shim must NOT contain jq (no logic — zero-logic contract C4).
  run grep -c 'jq' "$HARNESS_SHIM_DIR/claude-code-Stop.sh"
  # Allow 0 matches (grep -c returns exit 1 when 0 matches).
  [ "$status" -ne 0 ] || [ "$output" -eq 0 ]
}

@test "telemetry enable: Stop shim is executable" {
  mkdir -p .claude
  eidolons telemetry enable
  [ -x "$HARNESS_SHIM_DIR/claude-code-Stop.sh" ]
}

@test "telemetry enable: .claude/settings.json gains a Stop hook entry" {
  mkdir -p .claude
  run eidolons telemetry enable
  [ "$status" -eq 0 ]
  [ -f ".claude/settings.json" ]
  # The Stop key must exist in the hooks object.
  run jq -e '.hooks.Stop // empty' .claude/settings.json
  [ "$status" -eq 0 ]
}

@test "telemetry enable: Stop hook entry command points to the shim" {
  mkdir -p .claude
  eidolons telemetry enable
  # The command in the Stop hook must reference the shim path.
  _cmd="$(jq -r '.hooks.Stop[0].hooks[0].command // empty' .claude/settings.json)"
  [[ "$_cmd" == *"claude-code-Stop.sh" ]]
}

@test "telemetry enable: records shim path in eidolons.lock" {
  mkdir -p .claude
  eidolons telemetry enable
  grep -q 'claude-code-Stop.sh' eidolons.lock
}

# ─── AC-F5-2: idempotency ─────────────────────────────────────────────────────

@test "telemetry enable twice: settings.json is byte-identical (jq -cS)" {
  mkdir -p .claude
  eidolons telemetry enable
  _first="$(jq -cS . .claude/settings.json)"
  eidolons telemetry enable
  _second="$(jq -cS . .claude/settings.json)"
  [ "$_first" = "$_second" ]
}

@test "telemetry enable twice: shim file is unchanged (no duplicate hooks)" {
  mkdir -p .claude
  eidolons telemetry enable
  _shim1="$(cat "$HARNESS_SHIM_DIR/claude-code-Stop.sh")"
  eidolons telemetry enable
  _shim2="$(cat "$HARNESS_SHIM_DIR/claude-code-Stop.sh")"
  [ "$_shim1" = "$_shim2" ]
}

@test "telemetry enable twice: eidolons.lock has exactly one Stop shim entry" {
  mkdir -p .claude
  eidolons telemetry enable
  eidolons telemetry enable
  # grep -c returns 0 and exit 1 when no match; use true to absorb non-zero exit.
  _count="$(grep -c 'claude-code-Stop.sh' eidolons.lock 2>/dev/null; true)"
  # Trim any trailing newlines (bash command-substitution strips them already, but be safe).
  _count="$(printf '%s' "$_count" | tr -d '\n')"
  [ "$_count" -eq 1 ]
}

# ─── AC-F5-3: coexistence with UPS/SessionStart ───────────────────────────────

@test "telemetry enable: existing UPS hook in settings.json is preserved" {
  mkdir -p "$HARNESS_SHIM_DIR" .claude
  # Seed settings.json with a pre-existing UPS hook.
  jq -n \
    --arg ups "$HARNESS_SHIM_DIR/claude-code-UserPromptSubmit.sh" \
    '{"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": $ups}]}]}}' \
    > .claude/settings.json

  eidolons telemetry enable

  # UPS hook must still be present.
  run jq -e '.hooks.UserPromptSubmit // empty' .claude/settings.json
  [ "$status" -eq 0 ]
  # Stop hook must now also be present.
  run jq -e '.hooks.Stop // empty' .claude/settings.json
  [ "$status" -eq 0 ]
}

@test "telemetry enable: existing SessionStart hook in settings.json is preserved" {
  mkdir -p "$HARNESS_SHIM_DIR" .claude
  jq -n \
    --arg ss "$HARNESS_SHIM_DIR/claude-code-SessionStart.sh" \
    '{"hooks": {"SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": $ss}]}]}}' \
    > .claude/settings.json

  eidolons telemetry enable

  run jq -e '.hooks.SessionStart // empty' .claude/settings.json
  [ "$status" -eq 0 ]
  run jq -e '.hooks.Stop // empty' .claude/settings.json
  [ "$status" -eq 0 ]
}

@test "telemetry enable coexistence: UPS + SessionStart + Stop all present after enable" {
  mkdir -p "$HARNESS_SHIM_DIR" .claude
  # Simulate harness install having already registered UPS and SessionStart.
  jq -n \
    --arg ups "$HARNESS_SHIM_DIR/claude-code-UserPromptSubmit.sh" \
    --arg ss "$HARNESS_SHIM_DIR/claude-code-SessionStart.sh" \
    '{"hooks": {
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": $ups}]}],
        "SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": $ss}]}]
    }}' > .claude/settings.json

  eidolons telemetry enable

  run jq -e '.hooks.UserPromptSubmit // empty' .claude/settings.json
  [ "$status" -eq 0 ]
  run jq -e '.hooks.SessionStart // empty' .claude/settings.json
  [ "$status" -eq 0 ]
  run jq -e '.hooks.Stop // empty' .claude/settings.json
  [ "$status" -eq 0 ]
}

# ─── AC-F5-4: disable removes only Stop; siblings untouched ──────────────────

@test "telemetry disable after enable: Stop shim removed" {
  mkdir -p .claude
  eidolons telemetry enable
  [ -f "$HARNESS_SHIM_DIR/claude-code-Stop.sh" ]

  eidolons telemetry disable

  [ ! -f "$HARNESS_SHIM_DIR/claude-code-Stop.sh" ]
}

@test "telemetry disable after enable: Stop entry removed from settings.json" {
  mkdir -p .claude
  eidolons telemetry enable
  eidolons telemetry disable

  # settings.json must still exist but must have no Stop key.
  [ -f ".claude/settings.json" ]
  run jq -e '.hooks.Stop // empty' .claude/settings.json
  # empty → exit non-zero OR output is empty string.
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "telemetry disable after enable: Stop shim path removed from eidolons.lock" {
  mkdir -p .claude
  eidolons telemetry enable
  grep -q 'claude-code-Stop.sh' eidolons.lock

  eidolons telemetry disable

  run grep 'claude-code-Stop.sh' eidolons.lock
  [ "$status" -ne 0 ]
}

@test "telemetry disable: UPS and SessionStart in settings.json untouched" {
  mkdir -p "$HARNESS_SHIM_DIR" .claude
  jq -n \
    --arg ups "$HARNESS_SHIM_DIR/claude-code-UserPromptSubmit.sh" \
    --arg ss "$HARNESS_SHIM_DIR/claude-code-SessionStart.sh" \
    '{"hooks": {
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": $ups}]}],
        "SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": $ss}]}]
    }}' > .claude/settings.json

  eidolons telemetry enable
  eidolons telemetry disable

  # UPS and SessionStart must still be present.
  run jq -e '.hooks.UserPromptSubmit // empty' .claude/settings.json
  [ "$status" -eq 0 ]
  run jq -e '.hooks.SessionStart // empty' .claude/settings.json
  [ "$status" -eq 0 ]
  # Stop must be gone.
  run jq -e '.hooks.Stop // empty' .claude/settings.json
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "telemetry disable when not enabled: exit 0 (no-op)" {
  # No .claude or shim — disable should be a clean no-op.
  mkdir -p .claude
  run eidolons telemetry disable
  [ "$status" -eq 0 ]
}

@test "telemetry disable twice: idempotent, exit 0" {
  mkdir -p .claude
  eidolons telemetry enable
  eidolons telemetry disable
  run eidolons telemetry disable
  [ "$status" -eq 0 ]
}

# ─── AC-F5-5: end-to-end shim → capture → store ──────────────────────────────

@test "telemetry enable E2E: installed shim invocation captures an audited row" {
  mkdir -p .claude
  eidolons telemetry enable

  # Verify the shim was written.
  [ -f "$HARNESS_SHIM_DIR/claude-code-Stop.sh" ]

  # The shim's _eidolons_bin() calls 'command -v eidolons' first.
  # In the test environment the system eidolons may be a different (older) version.
  # Put a fake-bin dir on PATH with a wrapper that delegates to EIDOLONS_BIN so
  # the shim picks up the checkout's binary regardless of what is globally installed.
  _fake_bin="$BATS_TEST_TMPDIR/e2e-fake-bin"
  mkdir -p "$_fake_bin"
  cat > "$_fake_bin/eidolons" <<WRAPPER
#!/usr/bin/env bash
export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
exec bash "$EIDOLONS_BIN" "\$@"
WRAPPER
  chmod +x "$_fake_bin/eidolons"

  # Build the Stop event JSON pointing at the fixture transcript.
  _stop_event="$(jq -nc --arg tp "$FIXTURE_TRANSCRIPT" \
    '{"transcript_path": $tp, "hook_event_name": "Stop"}')"

  # Invoke the shim with the test-binary wrapper on PATH.
  # EIDOLONS_HOME is sandboxed; EIDOLONS_NEXUS points at the checkout.
  _shim_exit=0
  printf '%s' "$_stop_event" \
    | PATH="$_fake_bin:$PATH" \
      EIDOLONS_HOME="$EIDOLONS_HOME" \
      EIDOLONS_NEXUS="$EIDOLONS_ROOT" \
        bash "$HARNESS_SHIM_DIR/claude-code-Stop.sh" \
    || _shim_exit=$?
  # Shim must always exit 0 (fail-open contract).
  [ "$_shim_exit" -eq 0 ]

  # Assert that at least one audited row was written to the store.
  _store_root="$EIDOLONS_HOME/telemetry"
  _found_row=false
  for _f in "${_store_root}"/*/*.jsonl; do
    [ -f "$_f" ] || continue
    if grep -q '"source":"audited"' "$_f" 2>/dev/null; then
      _found_row=true
      break
    fi
  done
  [ "$_found_row" = "true" ]
}
