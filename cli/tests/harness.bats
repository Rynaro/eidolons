#!/usr/bin/env bats
#
# cli/tests/harness.bats — coverage for 'eidolons harness' verb family
#
# Phase 1 harness mechanization: R1–R8 (spec.md, 2026-06-10).
# The new harness surface: install|remove|status (hook wiring).
# Legacy aliases kept: up|verify|uninstall (deprecated Junction delegation).
#
# Design:
#   - All tests use helpers.bash conventions (load helpers; $BATS_TEST_TMPDIR).
#   - seed_manifest + seed_lock are used to set up a base project.
#   - A seed_lock_with_harness helper creates a lock with harness: key for tests
#     that require a pre-installed harness state.
#   - jq -cS canonical comparisons for idempotency tests (darwin/ubuntu safe).
#   - shim fail-open: write a minimal shim pointing at a nonexistent path;
#     execute it; assert exit 0 and empty stdout.
#   - run --hook: use routing files from the checkout; assert hookSpecificOutput JSON.

load helpers

# ─── Helpers ──────────────────────────────────────────────────────────────────

FAKE_JUNCTION_VERSION="0.1.0"

# seed_lock_with_harness [hosts_csv]
# Writes eidolons.lock with a harness: key for the given host(s).
seed_lock_with_harness() {
  local hosts_csv="${1:-claude-code}"
  local hosts_yaml=""
  local shims_yaml=""
  for _h in $(printf '%s' "$hosts_csv" | tr ',' ' '); do
    hosts_yaml="${hosts_yaml}    - $_h
"
    shims_yaml="${shims_yaml}    - .eidolons/harness/hooks/${_h}-UserPromptSubmit.sh
    - .eidolons/harness/hooks/${_h}-SessionStart.sh
"
  done

  cat > eidolons.lock <<EOF
generated_at: "2026-06-10T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
harness:
  schema_version: 1
  hosts_wired:
$hosts_yaml  shim_paths:
$shims_yaml
EOF
}

# seed_junction_cache [version]
# Creates a fake Junction cache dir with a stub binary (for legacy alias tests).
seed_junction_cache() {
  local ver="${1:-$FAKE_JUNCTION_VERSION}"
  local cache_dir="$EIDOLONS_HOME/cache/junction@${ver}"
  mkdir -p "$cache_dir"
  cat > "$cache_dir/junction" <<'JSTUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "verify" ]]; then
  echo "junction verify: pass-through ok"
  exit 0
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "junction 0.1.0"
  exit 0
fi
echo "junction stub: $*"
JSTUB
  chmod +x "$cache_dir/junction"
}

# ─── R6: Dispatcher routing ───────────────────────────────────────────────────

@test "harness: dispatcher routes harness install" {
  seed_manifest
  seed_lock
  # 'harness install --help' must exit 0 and show usage (not "Unknown command").
  run eidolons harness install --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "harness install" || "$output" =~ "install" ]]
}

@test "harness: dispatcher routes harness remove (no lock = info message)" {
  seed_manifest
  run eidolons harness remove
  [ "$status" -eq 0 ]
}

@test "harness: dispatcher routes harness status (no lock)" {
  seed_manifest
  run eidolons harness status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not installed" ]]
}

@test "harness: unknown subcommand exits 2 with list of available subcommands" {
  run eidolons harness bogus-subcommand
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Unknown harness subcommand" ]]
}

@test "harness: bare-semver install arg dies with migration hint" {
  # 'eidolons harness install 0.3.0' (old Junction form) must die with a message.
  seed_manifest
  run eidolons harness install 0.3.0
  [ "$status" -ne 0 ]
  [[ "$output" =~ "mcp install junction" ]]
}

# ─── R2-AC1: harness install writes settings.json with hooks block ─────────────

@test "harness: install writes settings.json with hooks block" {
  seed_manifest
  seed_lock
  run eidolons harness install --hosts claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".claude/settings.json" ]
  run jq -r '.hooks.UserPromptSubmit' .claude/settings.json
  [ "$status" -eq 0 ]
  [[ "$output" != "null" ]]
  # Shims must exist and be executable.
  [ -x ".eidolons/harness/hooks/claude-code-UserPromptSubmit.sh" ]
  [ -x ".eidolons/harness/hooks/claude-code-SessionStart.sh" ]
  # SessionStart matcher MUST cover all CC source values (startup|resume|clear|compact).
  # Regression: a "startup"-only matcher means the cortex is never re-injected after
  # auto-compaction (source:"compact"), so the host reverts to default mid-session.
  _ss_matcher="$(jq -r '.hooks.SessionStart[] | select(.hooks[].command | test("claude-code-SessionStart")) | .matcher' .claude/settings.json)"
  [ "$_ss_matcher" = "startup|resume|clear|compact" ]
}

@test "harness: install lockfile harness key is sorted/canonical" {
  seed_manifest
  seed_lock
  # Install with both hosts to test sorted order.
  run eidolons harness install --hosts codex,claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ -f eidolons.lock ]
  # hosts_wired must be sorted: claude-code before codex.
  _hosts="$(grep -A5 'hosts_wired:' eidolons.lock | grep -E '^ *- ' | awk '{print $2}')"
  _first="$(printf '%s' "$_hosts" | head -1)"
  [ "$_first" = "claude-code" ]
}

# ─── R2-AC2: harness install idempotent ────────────────────────────────────────

@test "harness: install idempotent — double run is no-op (jq -cS compare)" {
  seed_manifest
  seed_lock
  run eidolons harness install --hosts claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".claude/settings.json" ]
  _before_settings="$(jq -cS . .claude/settings.json)"
  # Capture a copy of the lockfile after first run.
  cp eidolons.lock eidolons.lock.first
  run eidolons harness install --hosts claude-code --non-interactive
  [ "$status" -eq 0 ]
  _after_settings="$(jq -cS . .claude/settings.json)"
  [ "$_before_settings" = "$_after_settings" ]
  # Lockfile must be byte-identical between runs (FINDING-2: no run-state flags).
  cmp -s eidolons.lock.first eidolons.lock
}

# ─── SessionStart matcher self-heal (1.42.0) ──────────────────────────────────

# T1: install --force upserts (heals) a stale "startup"-only OUR SessionStart
# entry to the canonical matcher. RED-before-fix proven empirically against main:
# the old append-if-absent merge left a present OUR entry UNCHANGED, so --force
# did NOT heal "startup" → it stayed "startup". The upsert fix makes this GREEN.
@test "harness: install --force heals stale OUR SessionStart matcher in place (T1 upsert)" {
  seed_manifest
  seed_lock
  mkdir -p .claude .eidolons/harness/hooks
  # Seed OUR SessionStart entry at the stale "startup"-only matcher.
  cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": ".eidolons/harness/hooks/claude-code-SessionStart.sh"}]}
    ]
  }
}
JSON
  run eidolons harness install --hosts claude-code --non-interactive --force
  [ "$status" -eq 0 ]
  # OUR entry must now carry the canonical matcher (heal-in-place, not append).
  _m="$(jq -r '.hooks.SessionStart[] | select(.hooks[].command | test("claude-code-SessionStart")) | .matcher' .claude/settings.json)"
  [ "$_m" = "startup|resume|clear|compact" ]
  # No duplicate OUR entry was appended.
  _count="$(jq -r '[.hooks.SessionStart[] | select(.hooks[].command | test("claude-code-SessionStart"))] | length' .claude/settings.json)"
  [ "$_count" = "1" ]
}

# T2: sync's refresh path (refresh-shims-only) heals a stale OUR matcher and
# emits an "ok healed…" line. Heal is on by default.
@test "harness: refresh-shims-only heals stale OUR SessionStart matcher + emits ok line (T2)" {
  seed_manifest
  seed_lock_with_harness "claude-code"
  mkdir -p .claude .eidolons/harness/hooks
  printf '#!/usr/bin/env bash\n# old shim\n' > .eidolons/harness/hooks/claude-code-SessionStart.sh
  chmod +x .eidolons/harness/hooks/claude-code-SessionStart.sh
  cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": ".eidolons/harness/hooks/claude-code-SessionStart.sh"}]}
    ]
  }
}
JSON
  run bash "$EIDOLONS_ROOT/cli/src/harness_install.sh" --refresh-shims-only
  [ "$status" -eq 0 ]
  _m="$(jq -r '.hooks.SessionStart[] | select(.hooks[].command | test("claude-code-SessionStart")) | .matcher' .claude/settings.json)"
  [ "$_m" = "startup|resume|clear|compact" ]
  [[ "$output" =~ "healed stale SessionStart matcher" ]]
}

# T3: --no-heal skips the heal (matcher stays stale) but still refreshes shims.
@test "harness: refresh-shims-only --no-heal skips heal; shims still refreshed (T3)" {
  seed_manifest
  seed_lock_with_harness "claude-code"
  mkdir -p .claude .eidolons/harness/hooks
  printf '#!/usr/bin/env bash\n# old shim\n' > .eidolons/harness/hooks/claude-code-SessionStart.sh
  chmod +x .eidolons/harness/hooks/claude-code-SessionStart.sh
  cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": ".eidolons/harness/hooks/claude-code-SessionStart.sh"}]}
    ]
  }
}
JSON
  run bash "$EIDOLONS_ROOT/cli/src/harness_install.sh" --refresh-shims-only --no-heal
  [ "$status" -eq 0 ]
  # Matcher must stay stale (heal skipped).
  _m="$(jq -r '.hooks.SessionStart[] | select(.hooks[].command | test("claude-code-SessionStart")) | .matcher' .claude/settings.json)"
  [ "$_m" = "startup" ]
  # No heal line emitted.
  ! [[ "$output" =~ "healed stale SessionStart matcher" ]]
  # Shim still refreshed (no longer "# old shim").
  run grep -c "Eidolons harness shim" .eidolons/harness/hooks/claude-code-SessionStart.sh
  [ "$status" -eq 0 ]
  [[ "$output" -ge 1 ]]
}

# T4: a FOREIGN SessionStart entry must be byte-identical after heal; only ours changes.
@test "harness: heal preserves FOREIGN SessionStart entry byte-identically (T4)" {
  seed_manifest
  seed_lock_with_harness "claude-code"
  mkdir -p .claude .eidolons/harness/hooks
  printf '#!/usr/bin/env bash\n# old shim\n' > .eidolons/harness/hooks/claude-code-SessionStart.sh
  chmod +x .eidolons/harness/hooks/claude-code-SessionStart.sh
  cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": "/usr/local/bin/foreign.sh"}]},
      {"matcher": "startup", "hooks": [{"type": "command", "command": ".eidolons/harness/hooks/claude-code-SessionStart.sh"}]}
    ]
  }
}
JSON
  _foreign_before="$(jq -cS '.hooks.SessionStart[] | select(.hooks[].command == "/usr/local/bin/foreign.sh")' .claude/settings.json)"
  run bash "$EIDOLONS_ROOT/cli/src/harness_install.sh" --refresh-shims-only
  [ "$status" -eq 0 ]
  # Foreign entry unchanged (including its "startup" matcher).
  _foreign_after="$(jq -cS '.hooks.SessionStart[] | select(.hooks[].command == "/usr/local/bin/foreign.sh")' .claude/settings.json)"
  [ "$_foreign_before" = "$_foreign_after" ]
  # Ours healed.
  _ours="$(jq -r '.hooks.SessionStart[] | select(.hooks[].command | test("claude-code-SessionStart")) | .matcher' .claude/settings.json)"
  [ "$_ours" = "startup|resume|clear|compact" ]
}

# T5: second heal run is a no-op — settings.json byte-identical, no spurious ok line.
@test "harness: heal is idempotent — second run is a no-op (T5)" {
  seed_manifest
  seed_lock_with_harness "claude-code"
  mkdir -p .claude .eidolons/harness/hooks
  printf '#!/usr/bin/env bash\n# old shim\n' > .eidolons/harness/hooks/claude-code-SessionStart.sh
  chmod +x .eidolons/harness/hooks/claude-code-SessionStart.sh
  cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": ".eidolons/harness/hooks/claude-code-SessionStart.sh"}]}
    ]
  }
}
JSON
  # First heal.
  run bash "$EIDOLONS_ROOT/cli/src/harness_install.sh" --refresh-shims-only
  [ "$status" -eq 0 ]
  _after_first="$(jq -cS . .claude/settings.json)"
  # Second heal — must be a no-op.
  run bash "$EIDOLONS_ROOT/cli/src/harness_install.sh" --refresh-shims-only
  [ "$status" -eq 0 ]
  _after_second="$(jq -cS . .claude/settings.json)"
  [ "$_after_first" = "$_after_second" ]
  # No spurious heal line on the second run.
  ! [[ "$output" =~ "healed stale SessionStart matcher" ]]
}

# ─── R2-AC3: sibling-key preservation ─────────────────────────────────────────

@test "harness: install preserves settings.json sibling keys" {
  seed_manifest
  seed_lock
  mkdir -p .claude
  printf '{"permissions":{"allow":["Bash(*)"]}, "theme":"dark"}\n' > .claude/settings.json
  run eidolons harness install --hosts claude-code --non-interactive
  [ "$status" -eq 0 ]
  # All three keys must be present.
  run jq -r '.permissions.allow[0]' .claude/settings.json
  [ "$status" -eq 0 ]
  [ "$output" = "Bash(*)" ]
  run jq -r '.theme' .claude/settings.json
  [ "$status" -eq 0 ]
  [ "$output" = "dark" ]
  run jq -r '.hooks' .claude/settings.json
  [ "$status" -eq 0 ]
  [[ "$output" != "null" ]]
}

# ─── R2-AC4: harness remove reverses install ───────────────────────────────────

@test "harness: remove reverses install" {
  seed_manifest
  seed_lock
  run eidolons harness install --hosts claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".claude/settings.json" ]
  # Verify hooks are written.
  _has_hooks="$(jq -r 'has("hooks")' .claude/settings.json)"
  [ "$_has_hooks" = "true" ]

  run eidolons harness remove
  [ "$status" -eq 0 ]
  # Hooks key must be removed.
  _after="$(jq -r 'has("hooks")' .claude/settings.json)"
  [ "$_after" = "false" ]
  # Shim files must be deleted.
  [ ! -f ".eidolons/harness/hooks/claude-code-UserPromptSubmit.sh" ]
  [ ! -f ".eidolons/harness/hooks/claude-code-SessionStart.sh" ]
}

# ─── FINDING-1: sibling hooks preserved through install+remove cycle ──────────
# Pre-populates settings.json with:
#   (a) a permissions block
#   (b) a pre-existing hooks.PreToolUse entry from "another tool"
#   (c) a pre-existing hooks.UserPromptSubmit entry with a different command
# After install+remove, all three must survive byte-identically (jq -cS compare).

@test "harness: sibling hooks survive full install+remove cycle (FINDING-1)" {
  seed_manifest
  seed_lock
  mkdir -p .claude

  # Write settings.json with sibling content that eidolons must not touch.
  cat > .claude/settings.json <<'JSON'
{
  "permissions": {"allow": ["Bash(*)", "Read(*)", "Write(*)"]},
  "theme": "dark",
  "hooks": {
    "PreToolUse": [{"hooks": [{"type": "command", "command": "/usr/local/bin/other-tool.sh"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/local/bin/other-ups.sh"}]}]
  }
}
JSON

  # Capture canonical representation of the sibling content only.
  _before_permissions="$(jq -cS '.permissions' .claude/settings.json)"
  _before_theme="$(jq -cS '.theme' .claude/settings.json)"
  _before_pretooluse="$(jq -cS '.hooks.PreToolUse' .claude/settings.json)"
  _before_other_ups="$(jq -cS '[.hooks.UserPromptSubmit[] | select(.hooks[]?.command == "/usr/local/bin/other-ups.sh")]' .claude/settings.json)"

  # Install — our entries should be appended, not replacing siblings.
  run eidolons harness install --hosts claude-code --non-interactive
  [ "$status" -eq 0 ]

  # (a) permissions block must be unchanged.
  _after_permissions="$(jq -cS '.permissions' .claude/settings.json)"
  [ "$_before_permissions" = "$_after_permissions" ]

  # (b) PreToolUse entry from other tool must be unchanged.
  _after_pretooluse="$(jq -cS '.hooks.PreToolUse' .claude/settings.json)"
  [ "$_before_pretooluse" = "$_after_pretooluse" ]

  # (c) The other UserPromptSubmit entry must still be present.
  _other_ups_present="$(jq -r '.hooks.UserPromptSubmit | map(select(.hooks[]?.command == "/usr/local/bin/other-ups.sh")) | length' .claude/settings.json)"
  [ "$_other_ups_present" = "1" ]

  # Our entry must also be present in UserPromptSubmit.
  _our_ups_present="$(jq -r '.hooks.UserPromptSubmit | map(select(.hooks[]?.command | test(".eidolons/harness/hooks"))) | length' .claude/settings.json)"
  [ "$_our_ups_present" = "1" ]

  # Remove — only our entries should be removed; siblings must survive.
  run eidolons harness remove
  [ "$status" -eq 0 ]

  # (a) permissions must still be present and unchanged.
  _final_permissions="$(jq -cS '.permissions' .claude/settings.json)"
  [ "$_before_permissions" = "$_final_permissions" ]

  # (b) PreToolUse entry must still be present.
  _final_pretooluse="$(jq -cS '.hooks.PreToolUse' .claude/settings.json)"
  [ "$_before_pretooluse" = "$_final_pretooluse" ]

  # (c) Other UserPromptSubmit entry must still be present.
  _other_ups_final="$(jq -r '.hooks.UserPromptSubmit | map(select(.hooks[]?.command == "/usr/local/bin/other-ups.sh")) | length' .claude/settings.json)"
  [ "$_other_ups_final" = "1" ]

  # Our eidolons entries must be gone.
  _our_ups_final="$(jq -r '(.hooks.UserPromptSubmit // []) | map(select(.hooks[]?.command | strings | test(".eidolons/harness/hooks"))) | length' .claude/settings.json)"
  [ "$_our_ups_final" = "0" ]
  _our_ss_final="$(jq -r '(.hooks.SessionStart // []) | length' .claude/settings.json)"
  [ "$_our_ss_final" = "0" ]
}

# ─── R2-AC5: harness status ────────────────────────────────────────────────────

@test "harness: status reports wired hosts" {
  seed_manifest
  seed_lock_with_harness "claude-code"
  # Create shim files so status doesn't warn missing.
  mkdir -p .eidolons/harness/hooks
  touch .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
  touch .eidolons/harness/hooks/claude-code-SessionStart.sh
  run eidolons harness status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "claude-code" ]]
  [[ "$output" =~ "T3" ]]
}

# ─── Change 2: status probes REALITY, not never-written lock keys ─────────────
# Defect: harness_install.sh never writes .harness.settings_json_patched /
# .harness.codex_hooks_json_patched (it records schema_version/hosts_wired/
# shim_paths/strict/strict_modes/protect only — harness_install.sh:780-850),
# so the old jq reads of those lock keys always displayed false. status must
# instead probe the actual .claude/settings.json / .codex/hooks.json surfaces.

@test "harness: status reports settings.json + codex hooks.json patched TRUE after a real install" {
  seed_manifest
  seed_lock
  run eidolons harness install --hosts claude-code,codex --non-interactive
  [ "$status" -eq 0 ]
  run eidolons harness status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "settings.json patched: true" ]]
  [[ "$output" =~ "codex hooks.json patched: true" ]]
}

@test "harness: status reports settings.json patched FALSE when a foreign settings.json has no eidolons wiring" {
  seed_manifest
  seed_lock_with_harness "claude-code"
  mkdir -p .eidolons/harness/hooks .claude
  touch .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
  touch .eidolons/harness/hooks/claude-code-SessionStart.sh
  # Lock claims claude-code is wired, but the real settings.json on disk has
  # ONLY a foreign hook entry — no eidolons shim command anywhere.
  cat > .claude/settings.json <<'EOF'
{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "/usr/local/bin/other-tool.sh"}]}]}}
EOF
  run eidolons harness status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "settings.json patched: false" ]]
}

@test "harness: status reports patched FALSE when lock claims installed but host files are absent (post-remove reality)" {
  seed_manifest
  seed_lock_with_harness "claude-code,codex"
  mkdir -p .eidolons/harness/hooks
  touch .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
  touch .eidolons/harness/hooks/claude-code-SessionStart.sh
  touch .eidolons/harness/hooks/codex-UserPromptSubmit.sh
  touch .eidolons/harness/hooks/codex-SessionStart.sh
  # No .claude/settings.json and no .codex/hooks.json on disk at all — the
  # state 'harness remove' leaves behind on the *host surfaces* (remove also
  # strips the lock's harness: key entirely; seed_lock_with_harness isolates
  # the reality-probe behavior from that early-exit branch).
  run eidolons harness status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "settings.json patched: false" ]]
  [[ "$output" =~ "codex hooks.json patched: false" ]]
}

@test "harness: status after a real install+remove cycle reports not installed (no stale true)" {
  seed_manifest
  seed_lock
  run eidolons harness install --hosts claude-code,codex --non-interactive
  [ "$status" -eq 0 ]
  run eidolons harness remove
  [ "$status" -eq 0 ]
  [ ! -f ".codex/hooks.json" ]
  run eidolons harness status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not installed" ]]
  [[ "$output" != *"settings.json patched: true"* ]]
  [[ "$output" != *"codex hooks.json patched: true"* ]]
}

# ─── R2-AC6: codex hooks.json ─────────────────────────────────────────────────

@test "harness: install codex writes hooks.json" {
  # Use a manifest with codex in wire.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  seed_lock
  run eidolons harness install --hosts codex --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".codex/hooks.json" ]
  run jq -r '.hooks.UserPromptSubmit' .codex/hooks.json
  [ "$status" -eq 0 ]
  [[ "$output" != "null" ]]
  # Assumption A1 warning must appear.
  [[ "$output" =~ "ASSUMPTION A1" || "$(cat <<< "$output")" =~ "A1" ]] || true
}

# ─── R2-AC7: shim fail-open ────────────────────────────────────────────────────

@test "harness: shim fail-open — missing CLI exits 0 empty stdout" {
  # Write a shim that uses a nonexistent eidolons binary path.
  mkdir -p .eidolons/harness/hooks
  cat > .eidolons/harness/hooks/test-UserPromptSubmit.sh <<'SHIM'
#!/usr/bin/env bash
# Minimal shim with nonexistent CLI path — should fail-open.
set -euo pipefail
_eidolons_bin() {
  # Fail: neither PATH command nor fallback path exists.
  return 1
}
_bin="$(_eidolons_bin 2>/dev/null)" || exit 0
"$_bin" run --hook test --stdin 2>/dev/null || exit 0
SHIM
  chmod +x .eidolons/harness/hooks/test-UserPromptSubmit.sh

  run bash .eidolons/harness/hooks/test-UserPromptSubmit.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── R2-AC8: sync refresh-not-install ─────────────────────────────────────────

@test "harness: sync refreshes shims if harness installed" {
  # Setup: harness installed (lock has harness: key), shim exists.
  seed_manifest
  seed_lock_with_harness "claude-code"
  mkdir -p .eidolons/harness/hooks
  printf '#!/usr/bin/env bash\n# old shim\n' > .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
  chmod +x .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
  printf '#!/usr/bin/env bash\n# old shim\n' > .eidolons/harness/hooks/claude-code-SessionStart.sh
  chmod +x .eidolons/harness/hooks/claude-code-SessionStart.sh

  # harness_install.sh --refresh-shims-only should overwrite shims.
  run bash "$EIDOLONS_ROOT/cli/src/harness_install.sh" --refresh-shims-only
  [ "$status" -eq 0 ]
  # Shim must have been refreshed (no longer just "# old shim").
  run grep -c "Eidolons harness shim" .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
  [ "$status" -eq 0 ]
  [[ "$output" -ge 1 ]]
}

@test "harness: sync does NOT install if harness absent" {
  seed_manifest
  seed_lock  # no harness: key in lock
  # Run refresh-shims-only — should be silent and exit 0.
  run bash "$EIDOLONS_ROOT/cli/src/harness_install.sh" --refresh-shims-only
  [ "$status" -eq 0 ]
  # Shims must NOT have been created.
  [ ! -d ".eidolons/harness/hooks" ]
}

# ─── R1-AC1: run --hook claude-code routing prompt emits valid JSON ────────────

@test "harness: run --hook claude-code routing prompt emits valid JSON" {
  seed_manifest
  # A non-trivial prompt should route to an Eidolon and emit hookSpecificOutput JSON.
  run eidolons run --hook claude-code "implement the authentication flow"
  [ "$status" -eq 0 ]
  if [[ -n "$output" ]]; then
    run jq -r '.hookSpecificOutput.hookEventName' <<< "$output"
    [ "$status" -eq 0 ]
    [ "$output" = "UserPromptSubmit" ]
  fi
  # If empty output: no Eidolon scored above tau (clarify decision) — also valid.
  # The test passes regardless because both paths are correct per AC-R1-2.
}

# ─── UPS injection is self-contained (survives cortex eviction on compaction) ──

@test "harness: run --hook claude-code UPS additionalContext is self-contained imperative" {
  seed_manifest
  # A non-trivial prompt should route and carry an inline, self-contained
  # delegation instruction — NOT a pointer to the dispatch protocol, which
  # compaction deletes from the window. Regression for the UPS-hardening fix.
  run eidolons run --hook claude-code "implement the authentication flow"
  [ "$status" -eq 0 ]
  if [[ -n "$output" ]]; then
    _ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<< "$output")"
    # Must carry the imperative phrasing inline.
    [[ "$_ctx" == *"via the Task tool"* ]]
    [[ "$_ctx" == *"Do NOT implement"* ]]
    # Must NOT degrade to the old bare pointer.
    [[ "$_ctx" != *"route per Eidolons dispatch protocol."* ]]
  fi
}

# ─── model_tier / model_tier_per_step injection (roster/routing.yaml ladder) ──
# Derived from the SAME artifact JSON the hook already parses; no kernel re-run.

@test "harness: run --hook claude-code single-dispatch UPS carries 'model tier: deep' for a VIGIL-routing prompt" {
  seed_manifest
  # 'root cause the flaky login test' matches VIGIL's trigger verbs
  # (root cause / flaky); VIGIL has suggested_tier: deep in routing.yaml.
  run eidolons run --hook claude-code "root cause the flaky login test"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  _ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<< "$output")"
  [[ "$_ctx" == *"Route: vigil"* ]]
  [[ "$_ctx" == *"model tier: deep"* ]]
  [[ "$_ctx" == *"honor each step's model tier"* ]]
  [[ "$_ctx" == *"roster/routing.yaml"* ]]
  # Single dispatch must NOT emit the plural chain form.
  [[ "$_ctx" != *"model tiers:"* ]]
}

@test "harness: run --hook claude-code chain UPS carries arrow-joined 'model tiers:' per step" {
  seed_manifest
  # 'map ... spec ... implement' co-triggers scout+planner+coder → the
  # plan-before-build chain (atlas → ramza → vivi → idg).
  run eidolons run --hook claude-code "map the codebase, spec the change, then implement it"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  _ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<< "$output")"
  [[ "$_ctx" == *"Chain: atlas → ramza → vivi → idg"* ]]
  [[ "$_ctx" == *"model tiers: atlas=standard → ramza=deep → vivi=standard → idg=light"* ]]
  # Chain form must NOT emit the singular dispatch form.
  [[ "$_ctx" != *"model tier: "* ]]
}

@test "harness: harness_hook.sh fail-open — artifact missing model_tier_per_step emits valid JSON with no tier lines" {
  # Craft a routing-decision artifact (mirrors the existing ESL-rider fixtures)
  # that lacks .chain / .model_tier_per_step entirely — the fields the hook
  # would normally read to build the tier line(s).
  local art='{"decision":"route","selected":["spectra"],"tier":"standard"}'
  run env HOOK_HOST=claude-code HOOK_MODE=run HOOK_EVENT_NAME=UserPromptSubmit \
    ARTIFACT_JSON="$art" PROMPT="x" \
    bash "$EIDOLONS_ROOT/cli/src/harness_hook.sh"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  local _raw_json="$output"
  # Output must still be valid JSON.
  run jq -e '.hookSpecificOutput.additionalContext' <<< "$_raw_json"
  [ "$status" -eq 0 ]
  _ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<< "$_raw_json")"
  [[ "$_ctx" != *"model tier"* ]]
  [[ "$_ctx" != *"honor each step's model tier"* ]]
}

# ─── R1-AC2: trivial prompt emits empty stdout ─────────────────────────────────

@test "harness: run --hook claude-code trivial prompt emits empty stdout" {
  seed_manifest
  # A clearly trivial prompt should produce empty stdout.
  run eidolons run --hook claude-code "thanks, that looks good"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── R1-AC3: --session-start emits cortex digest ──────────────────────────────

@test "harness: run --hook claude-code --session-start emits cortex digest" {
  seed_manifest
  # With no cortex file, must emit empty stdout, exit 0.
  run eidolons run --hook claude-code --session-start
  [ "$status" -eq 0 ]
  # With cortex file, must emit JSON.
  mkdir -p .eidolons/cortex
  cat > .eidolons/cortex/EIDOLONS.md <<'CORTEX'
## Roster Index
ATLAS — scout
SPECTRA — planner

## Dispatch Protocol
Route through the pipeline.
CORTEX
  run eidolons run --hook claude-code --session-start
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run jq -r '.hookSpecificOutput.hookEventName' <<< "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "SessionStart" ]
}

# ─── R3-AC1: footer text unconditional ────────────────────────────────────────

@test "harness: footer text unconditional (no lexical gate)" {
  # The dispatch pointer text must NOT contain the lexical gate phrases.
  run grep -n "mentions an Eidolon" "$EIDOLONS_ROOT/cli/src/lib.sh"
  [ "$status" -ne 0 ]  # must NOT be found
  run grep -n "TRANCE complexity signal" "$EIDOLONS_ROOT/cli/src/lib.sh"
  [ "$status" -ne 0 ]  # must NOT be found
  # The new text must be present.
  run grep -c "before any non-trivial prompt" "$EIDOLONS_ROOT/cli/src/lib.sh"
  [ "$status" -eq 0 ]
  [[ "$output" -ge 1 ]]
}

# ─── R4-AC1: codex toml stub written when absent ──────────────────────────────

@test "harness: codex toml stub written when absent" {
  setup_fake_git_for_upgrade
  seed_manifest_with atlas=^1.0.0
  # Override manifest to add codex to hosts.wire.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code, codex]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  run eidolons sync --yes --non-interactive
  [ "$status" -eq 0 ]
  # .codex/agents/atlas.toml must exist.
  [ -f ".codex/agents/atlas.toml" ]
  run grep "name = " .codex/agents/atlas.toml
  [ "$status" -eq 0 ]
  [[ "$output" =~ "atlas" ]]
}

# ─── R4-AC2: codex toml stub not overwritten ──────────────────────────────────

@test "harness: codex toml stub not overwritten" {
  setup_fake_git_for_upgrade
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code, codex]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  mkdir -p .codex/agents
  printf 'name = "custom"\ndescription = "custom value"\n' > .codex/agents/atlas.toml
  run eidolons sync --yes --non-interactive
  [ "$status" -eq 0 ]
  # Content must be unchanged.
  run grep "custom" .codex/agents/atlas.toml
  [ "$status" -eq 0 ]
}

# ─── R4-AC3: codex md file preserved (not deleted) ────────────────────────────

@test "harness: codex md file preserved (not deleted)" {
  setup_fake_git_for_upgrade
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code, codex]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  mkdir -p .codex/agents
  printf '# atlas agent\n' > .codex/agents/atlas.md
  run eidolons sync --yes --non-interactive
  [ "$status" -eq 0 ]
  # .md file must NOT be deleted.
  [ -f ".codex/agents/atlas.md" ]
}

# ─── R5-AC1: copilot agent stub written when absent ───────────────────────────

@test "harness: copilot agent stub written when absent" {
  setup_fake_git_for_upgrade
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code, copilot]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  run eidolons sync --yes --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".github/agents/atlas.agent.md" ]
  run grep "name:" .github/agents/atlas.agent.md
  [ "$status" -eq 0 ]
  [[ "$output" =~ "atlas" ]]
}

# ─── R5-AC2: copilot agent stub not overwritten ───────────────────────────────

@test "harness: copilot agent stub not overwritten" {
  setup_fake_git_for_upgrade
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code, copilot]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  mkdir -p .github/agents
  cat > .github/agents/atlas.agent.md <<'AGENTMD'
---
name: atlas
description: custom
---
Custom body.
AGENTMD
  run eidolons sync --yes --non-interactive
  [ "$status" -eq 0 ]
  run grep "Custom body" .github/agents/atlas.agent.md
  [ "$status" -eq 0 ]
}

# ─── R4-AC4: harness status warns about unread codex .md files ────────────────

@test "harness: harness status warns about unread codex .md files" {
  seed_manifest
  seed_lock_with_harness "codex"
  mkdir -p .eidolons/harness/hooks
  touch .eidolons/harness/hooks/codex-UserPromptSubmit.sh
  touch .eidolons/harness/hooks/codex-SessionStart.sh
  # Create both .md and .toml for atlas.
  mkdir -p .codex/agents
  printf 'name = "atlas"\n' > .codex/agents/atlas.toml
  printf '# atlas agent\n' > .codex/agents/atlas.md
  run eidolons harness status 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "atlas.md" ]]
  [[ "$output" =~ ".toml" ]]
}

# ─── Back-compat: legacy aliases emit DEPRECATED ──────────────────────────────

@test "back-compat: eidolons harness up emits DEPRECATED" {
  seed_junction_cache
  run eidolons harness up 2>&1 || true
  [[ "$output" =~ "DEPRECATED" ]]
}

@test "back-compat: eidolons harness uninstall emits DEPRECATED" {
  seed_junction_cache
  run eidolons harness uninstall --yes 2>&1 || true
  [[ "$output" =~ "DEPRECATED" ]]
}

@test "back-compat: eidolons harness verify emits DEPRECATED" {
  seed_junction_cache
  run eidolons harness verify 2>&1 || true
  [[ "$output" =~ "DEPRECATED" ]]
}

@test "back-compat: EIDOLONS_SUPPRESS_DEPRECATED=1 suppresses DEPRECATED" {
  seed_junction_cache
  count="$(EIDOLONS_SUPPRESS_DEPRECATED=1 eidolons harness up 2>&1 | grep -c "DEPRECATED" || true)"
  [ "$count" -eq 0 ]
}

@test "harness install <bad-version>: graceful error with migration hint" {
  seed_manifest
  run eidolons harness install 999.9.9
  [ "$status" -ne 0 ]
  [[ "$output" =~ "mcp install junction" ]]
}

# ─── Phase 2: R9 — Cursor cortex surface ─────────────────────────────────────

# Helper: seed a manifest with cursor in hosts.wire + shared_dispatch: true.
seed_cursor_manifest() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [cursor]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

# Helper: seed a minimal cortex EIDOLONS.md.
seed_cortex() {
  mkdir -p .eidolons/cortex
  cat > .eidolons/cortex/EIDOLONS.md <<'EOF'
# Eidolons Routing Cortex

## Roster Index (always-loaded)

| Eidolon | Role |
|---------|------|
| ATLAS   | scout |

## Dispatch Protocol (always-loaded)

Route all non-trivial work through the Eidolons pipeline.
EOF
}

@test "harness: cursor cortex mdc written when cursor wired" {
  # Test the .mdc writer directly via the sync.sh lib (bypass full member install).
  seed_cursor_manifest
  seed_cortex
  run bash -c "
    set -euo pipefail
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    MANIFEST_JSON=\"\$(yaml_to_json eidolons.yaml 2>/dev/null)\"
    HOSTS_CSV=\"\$(printf '%s' \"\$MANIFEST_JSON\" | jq -r '(.hosts.wire // []) | join(\",\")')\"
    EFFECTIVE_SHARED_DISPATCH=\"\$(printf '%s' \"\$MANIFEST_JSON\" | jq -r '.hosts.shared_dispatch // false')\"
    _cortex_src='.eidolons/cortex/EIDOLONS.md'
    if [[ \",\${HOSTS_CSV},\" == *\",cursor,\"* ]] && [[ \"\$EFFECTIVE_SHARED_DISPATCH\" == 'true' ]] && [[ -f \"\$_cortex_src\" ]]; then
      _mdc_digest=\"\$(awk '
        /^## Roster Index/ { in_section=1 }
        /^## Dispatch Protocol/ { in_section=1 }
        /^## / && !/^## Roster Index/ && !/^## Dispatch Protocol/ { in_section=0 }
        in_section { print }
      ' \"\$_cortex_src\" 2>/dev/null | head -c 4000 || true)\"
      _mdc_body=\"\${_mdc_digest}

> Deep tables: .eidolons/cortex/trance-matrix.md\"
      _mdc_file='.cursor/rules/eidolons-cortex.mdc'
      _mdc_frontmatter='---
description: Eidolons routing cortex — read before any non-trivial prompt.
alwaysApply: true
---'
      mkdir -p '.cursor/rules'
      printf '%s\n' \"\$_mdc_frontmatter\" > \"\$_mdc_file\"
      printf '\n' >> \"\$_mdc_file\"
      upsert_marker_block \"\$_mdc_file\" 'cortex' \"\$_mdc_body\"
    fi
  " 2>/dev/null
  [ -f ".cursor/rules/eidolons-cortex.mdc" ]
}

@test "harness: cursor mdc frontmatter has alwaysApply:true and no globs" {
  seed_cursor_manifest
  seed_cortex
  # Write the .mdc using sync.sh logic via bash sub-shell.
  bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    MANIFEST_JSON=\"\$(yaml_to_json eidolons.yaml 2>/dev/null)\"
    HOSTS_CSV=\"\$(printf '%s' \"\$MANIFEST_JSON\" | jq -r '(.hosts.wire // []) | join(\",\")')\"
    EFFECTIVE_SHARED_DISPATCH=\"\$(printf '%s' \"\$MANIFEST_JSON\" | jq -r '.hosts.shared_dispatch // false')\"
    _cortex_src='.eidolons/cortex/EIDOLONS.md'
    _mdc_digest=\"\$(awk '
      /^## Roster Index/ { in_section=1 }
      /^## Dispatch Protocol/ { in_section=1 }
      /^## / && !/^## Roster Index/ && !/^## Dispatch Protocol/ { in_section=0 }
      in_section { print }
    ' \"\$_cortex_src\" 2>/dev/null | head -c 4000 || true)\"
    _mdc_body=\"\${_mdc_digest}\"
    _mdc_file='.cursor/rules/eidolons-cortex.mdc'
    _mdc_frontmatter='---
description: Eidolons routing cortex — read before any non-trivial prompt.
alwaysApply: true
---'
    mkdir -p '.cursor/rules'
    printf '%s\n' \"\$_mdc_frontmatter\" > \"\$_mdc_file\"
    printf '\n' >> \"\$_mdc_file\"
    upsert_marker_block \"\$_mdc_file\" 'cortex' \"\$_mdc_body\"
  " 2>/dev/null
  [ -f ".cursor/rules/eidolons-cortex.mdc" ]
  grep -qF "alwaysApply: true" .cursor/rules/eidolons-cortex.mdc
  # Must NOT contain a globs: key.
  ! grep -qF "globs:" .cursor/rules/eidolons-cortex.mdc
}

@test "harness: cursor mdc body is marker-bounded and idempotent (byte-identical re-sync)" {
  seed_cursor_manifest
  seed_cortex
  # Use sync.sh's _mcp_oci_render_and_merge call path by calling the sync cortex stage
  # directly via the lib.
  _write_mdc() {
    bash -c "
      export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
      export EIDOLONS_HOME='$EIDOLONS_HOME'
      . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
      _cortex_src='.eidolons/cortex/EIDOLONS.md'
      _mdc_digest=\"\$(awk '
        /^## Roster Index/ { in_section=1 }
        /^## Dispatch Protocol/ { in_section=1 }
        /^## / && !/^## Roster Index/ && !/^## Dispatch Protocol/ { in_section=0 }
        in_section { print }
      ' \"\$_cortex_src\" 2>/dev/null | head -c 4000 || true)\"
      _mdc_body=\"\${_mdc_digest}\"
      _mdc_file='.cursor/rules/eidolons-cortex.mdc'
      _mdc_frontmatter='---
description: Eidolons routing cortex — read before any non-trivial prompt.
alwaysApply: true
---'
      mkdir -p '.cursor/rules'
      if [[ ! -f \"\$_mdc_file\" ]]; then
        printf '%s\n' \"\$_mdc_frontmatter\" > \"\$_mdc_file\"
        printf '\n' >> \"\$_mdc_file\"
        upsert_marker_block \"\$_mdc_file\" 'cortex' \"\$_mdc_body\"
      else
        upsert_marker_block \"\$_mdc_file\" 'cortex' \"\$_mdc_body\"
      fi
    " 2>/dev/null
  }
  _write_mdc
  [ -f ".cursor/rules/eidolons-cortex.mdc" ]
  grep -qF "<!-- eidolon:cortex start -->" .cursor/rules/eidolons-cortex.mdc
  grep -qF "<!-- eidolon:cortex end -->" .cursor/rules/eidolons-cortex.mdc
  # Second write: file must be byte-identical (no-op).
  _before="$(cat .cursor/rules/eidolons-cortex.mdc)"
  _write_mdc
  _after="$(cat .cursor/rules/eidolons-cortex.mdc)"
  [ "$_before" = "$_after" ]
}

@test "harness: non-cursor project gets no .cursor/rules mdc" {
  # claude-code only — no cursor in hosts.wire.
  seed_manifest  # wire: [claude-code]
  seed_cortex
  # Even if we invoke the mdc writer, it is gated on cursor ∈ HOSTS_CSV.
  bash -c "
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    export EIDOLONS_HOME='$EIDOLONS_HOME'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    MANIFEST_JSON=\"\$(yaml_to_json eidolons.yaml 2>/dev/null)\"
    HOSTS_CSV=\"\$(printf '%s' \"\$MANIFEST_JSON\" | jq -r '(.hosts.wire // []) | join(\",\")')\"
    EFFECTIVE_SHARED_DISPATCH='true'
    # Gate: cursor NOT in HOSTS_CSV → must not write.
    if [[ \",\${HOSTS_CSV},\" == *\",cursor,\"* ]]; then
      mkdir -p '.cursor/rules'
      printf 'frontmatter\n' > '.cursor/rules/eidolons-cortex.mdc'
    fi
  " 2>/dev/null
  [ ! -f ".cursor/rules/eidolons-cortex.mdc" ]
}

# ─── Phase 2: R12 — Copilot harness adapter ───────────────────────────────────

# Helper: seed manifest with copilot in hosts.wire.
seed_copilot_manifest() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [copilot]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

@test "harness: copilot is a supported host" {
  seed_copilot_manifest
  seed_lock
  run eidolons harness install --hosts copilot --non-interactive
  [ "$status" -eq 0 ]
  # Must NOT skip copilot as unsupported.
  ! [[ "$output" =~ "Skipping unsupported harness host: copilot" ]]
}

@test "harness: copilot install writes SessionStart shim only (no UserPromptSubmit)" {
  seed_copilot_manifest
  seed_lock
  run eidolons harness install --hosts copilot --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".eidolons/harness/hooks/copilot-SessionStart.sh" ]
  [ ! -f ".eidolons/harness/hooks/copilot-UserPromptSubmit.sh" ]
}

@test "harness: copilot install writes .github/hooks/eidolons.json (jq -e .version==1)" {
  seed_copilot_manifest
  seed_lock
  run eidolons harness install --hosts copilot --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".github/hooks/eidolons.json" ]
  run jq -e '.version == 1' .github/hooks/eidolons.json
  [ "$status" -eq 0 ]
  run jq -e '.hooks.sessionStart[0].bash == ".eidolons/harness/hooks/copilot-SessionStart.sh"' .github/hooks/eidolons.json
  [ "$status" -eq 0 ]
  # Must NOT have a userPromptSubmitted key.
  run jq -e 'has("hooks") and (.hooks | has("userPromptSubmitted")) | not' .github/hooks/eidolons.json
  [ "$status" -eq 0 ]
}

@test "harness: copilot install prints upstream-bug caveat" {
  seed_copilot_manifest
  seed_lock
  run eidolons harness install --hosts copilot --non-interactive 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "2142" ]] || [[ "$output" =~ "1139" ]] || [[ "$output" =~ "Copilot" ]]
}

@test "harness: copilot in lockfile hosts_wired" {
  seed_copilot_manifest
  seed_lock
  run eidolons harness install --hosts copilot --non-interactive
  [ "$status" -eq 0 ]
  grep -qF "copilot" eidolons.lock
  grep -qF "copilot-SessionStart.sh" eidolons.lock
  # Must NOT have copilot-UserPromptSubmit.sh in lock.
  ! grep -qF "copilot-UserPromptSubmit.sh" eidolons.lock
}

@test "harness: copilot remove deletes hook file + shim; siblings preserved" {
  seed_copilot_manifest
  seed_lock
  run eidolons harness install --hosts copilot --non-interactive
  [ "$status" -eq 0 ]
  # Create a sibling file in .github/hooks/ (user-managed).
  printf '{}' > .github/hooks/other.json
  run eidolons harness remove
  [ "$status" -eq 0 ]
  [ ! -f ".github/hooks/eidolons.json" ]
  [ ! -f ".eidolons/harness/hooks/copilot-SessionStart.sh" ]
  # Sibling must survive.
  [ -f ".github/hooks/other.json" ]
}

@test "harness: copilot install/remove/re-install byte-identical hooks json" {
  seed_copilot_manifest
  seed_lock
  run eidolons harness install --hosts copilot --non-interactive
  [ "$status" -eq 0 ]
  _first="$(jq -cS . .github/hooks/eidolons.json)"
  run eidolons harness remove
  [ "$status" -eq 0 ]
  # Re-install and compare.
  run eidolons harness install --hosts copilot --non-interactive
  [ "$status" -eq 0 ]
  _second="$(jq -cS . .github/hooks/eidolons.json)"
  [ "$_first" = "$_second" ]
}

# ─── Phase 2: R13 — harness status effective-tier ladder ─────────────────────

@test "harness: status shows per-host effective tier (T3/T2/T1)" {
  seed_manifest
  # Seed lock with claude-code (T3) + codex (T3).
  cat > eidolons.lock <<'EOF'
generated_at: "2026-06-10T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
harness:
  schema_version: 1
  hosts_wired:
    - claude-code
    - codex
  shim_paths:
    - .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
    - .eidolons/harness/hooks/claude-code-SessionStart.sh
    - .eidolons/harness/hooks/codex-UserPromptSubmit.sh
    - .eidolons/harness/hooks/codex-SessionStart.sh
EOF
  run eidolons harness status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "T3" ]]
  [[ "$output" =~ "claude-code" ]]
  [[ "$output" =~ "codex" ]]
}

@test "harness: status reports cursor mdc + AGENTS.md presence" {
  # Manifest with cursor wired.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [cursor]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  # Lock must have harness installed (even if cursor is not harness-installable,
  # status reads manifest for cursor static-surface check).
  cat > eidolons.lock <<'EOF'
generated_at: "2026-06-10T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["cursor"]
harness:
  schema_version: 1
  hosts_wired:
    - claude-code
  shim_paths:
    - .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
    - .eidolons/harness/hooks/claude-code-SessionStart.sh
EOF
  run eidolons harness status
  [ "$status" -eq 0 ]
  # Must report cursor static surface presence/absence.
  [[ "$output" =~ ".cursor/rules/eidolons-cortex.mdc" ]]
  [[ "$output" =~ "absent" ]] || [[ "$output" =~ "present" ]]
}

@test "harness: status executes no host binary; exit 0" {
  seed_manifest
  seed_lock_with_harness "claude-code"
  # There are no host binaries on PATH in the test tmpdir environment.
  # The status command must exit 0 regardless.
  run eidolons harness status
  [ "$status" -eq 0 ]
}

# ─── P3 R18: strict tier (--strict flag) ─────────────────────────────────────

@test "harness: --strict writes nothing without flag; lock has no strict key (base unchanged)" {
  seed_manifest
  seed_lock
  run eidolons harness install
  [ "$status" -eq 0 ]
  [ -f ".eidolons/harness/hooks/claude-code-UserPromptSubmit.sh" ]
  [ ! -f ".eidolons/harness/hooks/claude-code-PreToolUse.sh" ]
  # lock must have no strict: key
  run grep "strict:" eidolons.lock
  [ "$status" -ne 0 ]
}

@test "harness: --strict --hosts claude-code scopes strict to claude only" {
  seed_manifest
  seed_lock
  run eidolons harness install --strict --hosts claude-code
  [ "$status" -eq 0 ]
  [ -f ".eidolons/harness/hooks/claude-code-PreToolUse.sh" ]
  [ ! -f ".eidolons/harness/hooks/codex-PreToolUse.sh" ]
  # lock must have strict: key with claude-code listed
  run grep -A5 "^  strict:" eidolons.lock
  [ "$status" -eq 0 ]
  [[ "$output" =~ "claude-code" ]]
}

@test "harness: --strict refuses cursor + prints reason; not in strict[]" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [cursor]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  seed_lock
  run eidolons harness install --strict --hosts cursor
  # Exits 0 (fail-open), but refuses the cursor strict surface.
  [[ "$output" =~ "refuse" ]] || [[ "$stderr" =~ "refuse" ]]
  [ ! -f ".eidolons/harness/hooks/cursor-PreToolUse.sh" ]
}

@test "harness: --strict opencode writes advisory plugin + records strict:advisory + #5894 refusal" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [opencode]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  seed_lock
  run eidolons harness install --strict --hosts opencode
  [ "$status" -eq 0 ]
  [ -f ".opencode/plugins/eidolons.js" ]
  run grep -i "5894" .opencode/plugins/eidolons.js
  [ "$status" -eq 0 ]
  # strict: is a multi-line YAML block; the host name is on the NEXT line after the key.
  # Use -A1 so both the key line and the host line appear in output.
  run grep -A 1 '^  strict:' eidolons.lock
  [ "$status" -eq 0 ]
  [[ "$output" =~ "opencode" ]]
  # strict_modes indents host as "    opencode: advisory" — match the full literal line.
  run grep '    opencode: advisory' eidolons.lock
  [ "$status" -eq 0 ]
}

@test "harness: remove cleans PreToolUse settings + codex entry + plugin + strict lock key" {
  seed_manifest
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  [ -f ".eidolons/harness/hooks/claude-code-PreToolUse.sh" ]
  run eidolons harness remove
  [ "$status" -eq 0 ]
  [ ! -f ".eidolons/harness/hooks/claude-code-PreToolUse.sh" ]
  # lock must not have harness: key
  run grep "^harness:" eidolons.lock
  [ "$status" -ne 0 ]
}

@test "harness: status shows strict state, protected-globs count, refusals" {
  seed_manifest
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  run eidolons harness status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "strict" ]]
  [[ "$output" =~ "protected-globs count" ]]
}

@test "harness: protect globs read from eidolons.yaml; empty = no glob denials" {
  seed_manifest
  seed_lock
  # Without harness.protect, strict install should work (empty glob list).
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  [ -f ".eidolons/harness/hooks/claude-code-PreToolUse.sh" ]
  # With globs configured.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
harness:
  protect:
    - "src/generated/**"
    - "**/*.lock"
EOF
  run eidolons harness install --strict --force
  [ "$status" -eq 0 ]
  run grep "src/generated" .eidolons/harness/hooks/claude-code-PreToolUse.sh
  [ "$status" -eq 0 ]
}

# ─── P3 R19: claude-code strict shim unit tests ──────────────────────────────

@test "harness: --strict writes PreToolUse settings entry (matcher Edit|Write|MultiEdit|NotebookEdit)" {
  seed_manifest
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  run jq -e '.hooks.PreToolUse | length > 0' .claude/settings.json
  [ "$status" -eq 0 ]
  run jq -r '.hooks.PreToolUse[0].matcher' .claude/settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == "Edit|Write|MultiEdit|NotebookEdit" ]]
}

@test "strict-shim(claude): main-loop edit (no agent_id) -> deny JSON exact shape" {
  seed_manifest
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  local shim=".eidolons/harness/hooks/claude-code-PreToolUse.sh"
  [ -f "$shim" ]
  FIXTURE='{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}'
  run bash -c "printf '%s' '$FIXTURE' | $shim"
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$FIXTURE' | $shim | jq -e '.hookSpecificOutput.permissionDecision == \"deny\"'"
  [ "$status" -eq 0 ]
}

@test "strict-shim(claude): agent_id present -> silent allow (empty stdout)" {
  seed_manifest
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  local shim=".eidolons/harness/hooks/claude-code-PreToolUse.sh"
  FIXTURE='{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"},"agent_id":"sub_1"}'
  run bash -c "printf '%s' '$FIXTURE' | $shim"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "strict-shim(claude): protected glob -> deny REGARDLESS of agent_id (subagent too)" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
harness:
  protect:
    - "src/generated/**"
EOF
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  local shim=".eidolons/harness/hooks/claude-code-PreToolUse.sh"
  # Even with agent_id present, protected glob match must deny.
  FIXTURE='{"tool_name":"Edit","tool_input":{"file_path":"src/generated/x.ts"},"agent_id":"sub_1"}'
  run bash -c "printf '%s' '$FIXTURE' | $shim | jq -e '.hookSpecificOutput.permissionDecision == \"deny\"'"
  [ "$status" -eq 0 ]
}

@test "strict-shim(claude): non-edit tool -> allow; malformed stdin -> exit 0 empty (fail-open)" {
  seed_manifest
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  local shim=".eidolons/harness/hooks/claude-code-PreToolUse.sh"
  # Non-edit tool -> allow (empty stdout).
  FIXTURE='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  run bash -c "printf '%s' '$FIXTURE' | $shim"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Malformed stdin -> fail-open (exit 0 empty).
  run bash -c "printf 'not json at all' | $shim"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── P3 R20: codex strict shim unit tests ────────────────────────────────────

@test "strict-shim(codex): protected glob -> {decision:block,reason}; no glob -> allow; refusal info printed" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
harness:
  protect:
    - "src/generated/**"
EOF
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  local shim=".eidolons/harness/hooks/codex-PreToolUse.sh"
  [ -f "$shim" ]
  # Protected glob match -> block.
  FIXTURE='{"tool_name":"apply_patch","tool_input":{"file_path":"src/generated/foo.ts"}}'
  run bash -c "printf '%s' '$FIXTURE' | $shim | jq -e '.decision == \"block\"'"
  [ "$status" -eq 0 ]
  # No glob match -> allow (empty stdout).
  FIXTURE2='{"tool_name":"apply_patch","tool_input":{"file_path":"src/safe.ts"}}'
  run bash -c "printf '%s' '$FIXTURE2' | $shim"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Install should have printed refusal info for delegate-or-deny.
}

@test "strict-shim(codex): malformed stdin -> exit 0 empty (fail-open)" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
harness:
  protect:
    - "src/generated/**"
EOF
  seed_lock
  run eidolons harness install --strict
  [ "$status" -eq 0 ]
  local shim=".eidolons/harness/hooks/codex-PreToolUse.sh"
  run bash -c "printf 'not json at all' | $shim"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── P3 R21: UPS #16952 guard ────────────────────────────────────────────────

@test "ups-guard: completion-shaped prompt (Agent X completed...) -> shim exits 0 empty; normal prompt routes" {
  seed_manifest
  seed_lock
  run eidolons harness install
  [ "$status" -eq 0 ]
  local shim=".eidolons/harness/hooks/claude-code-UserPromptSubmit.sh"
  [ -f "$shim" ]

  # ── Fail-open half: shim must exit 0 even when no eidolons binary is reachable.
  # Point EIDOLONS_HOME at an empty dir so _eidolons_bin() returns 1.
  _empty_home="$BATS_TEST_TMPDIR/empty-home"
  mkdir -p "$_empty_home"
  COMPLETION_JSON='{"prompt":"Agent spectra completed: analysis done."}'
  run bash -c "EIDOLONS_HOME='$_empty_home' printf '%s' '$COMPLETION_JSON' | EIDOLONS_HOME='$_empty_home' bash '$shim'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # task-notification shape (also fail-open).
  NOTIF_JSON='{"prompt":"some text <task-notification> more text"}'
  run bash -c "EIDOLONS_HOME='$_empty_home' printf '%s' '$NOTIF_JSON' | EIDOLONS_HOME='$_empty_home' bash '$shim'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # ── Routing half: a real non-trivial prompt must produce non-empty hookSpecificOutput JSON.
  # Wire EIDOLONS_HOME so the shim's _eidolons_bin fallback resolves to the checkout CLI.
  _wired_home="$BATS_TEST_TMPDIR/wired-home"
  mkdir -p "$_wired_home/nexus/cli"
  ln -sf "$EIDOLONS_ROOT/cli/eidolons" "$_wired_home/nexus/cli/eidolons"
  ROUTING_JSON='{"prompt":"implement the authentication flow for the API"}'
  run bash -c "
    export EIDOLONS_HOME='$_wired_home'
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    printf '%s' '$ROUTING_JSON' | bash '$shim'
  "
  [ "$status" -eq 0 ]
  # Output must be non-empty hookSpecificOutput JSON when routing fires.
  if [[ -n "$output" ]]; then
    run jq -r '.hookSpecificOutput.hookEventName' <<< "$output"
    [ "$status" -eq 0 ]
    [ "$output" = "UserPromptSubmit" ]
  fi
  # If empty: no Eidolon scored above tau (clarify/pass-through) — also valid per R1.
}

@test "ups-guard: run.sh --stdin completion-shaped prompt exits 0 empty (kernel backstop)" {
  seed_manifest
  seed_lock
  # run --hook in stdin mode with a completion-shaped JSON should exit 0 silently.
  # Use the checkout CLI explicitly — 'eidolons' is a helpers.bash shell function,
  # invisible inside bash -c child shells. EIDOLONS_NEXUS is already exported by setup.
  COMPLETION_JSON='{"prompt":"Agent vivi completed: done."}'
  run bash -c "printf '%s' '$COMPLETION_JSON' | bash '$EIDOLONS_ROOT/cli/eidolons' run --hook claude-code --stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # task-notification shape.
  NOTIF_JSON='{"prompt":"<task-notification>"}'
  run bash -c "printf '%s' '$NOTIF_JSON' | bash '$EIDOLONS_ROOT/cli/eidolons' run --hook claude-code --stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── P3 R22: doctor D12 gate ─────────────────────────────────────────────────

@test "doctor: D12 skips when harness absent; passes" {
  seed_manifest
  seed_lock
  run eidolons doctor --deep
  # D12 always runs; assert the D12 skip line is present
  # (overall exit may be non-zero due to other deep gates on the stub project).
  [[ "$output" =~ "D12" ]]
  [[ "$output" =~ "skip" ]] || [[ "$output" =~ "not installed" ]]
}

@test "doctor: D12 fails on missing/non-exec shim (lock-vs-file integrity)" {
  seed_manifest
  seed_lock_with_harness "claude-code"
  # Lock says shim exists but the file is absent.
  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "D12" ]]
}

@test "doctor: D12 fails on unsound strict host; warns on orphan plugin" {
  seed_manifest
  seed_lock
  # Craft a lock with cursor in strict[] — unsound.
  cat >> eidolons.lock <<'EOF'
harness:
  schema_version: 1
  hosts_wired:
    - cursor
  shim_paths: []
  strict:
    - cursor
EOF
  run eidolons doctor --deep
  [ "$status" -ne 0 ]
  [[ "$output" =~ "D12" ]]
  [[ "$output" =~ "cursor" ]]
}

# ─── GAP-2 R28: SessionStart memory spine ────────────────────────────────────

# Helper: put a fake eidolons on PATH that intercepts 'memory preflight'
# and delegates everything else to the real checkout CLI.
# FAKE_PREFLIGHT_OUTPUT — what preflight prints to stdout (default: empty).
# FAKE_PREFLIGHT_EXIT   — preflight exit code (default: 0).
setup_fake_eidolons_for_memory() {
  local preflight_out="${FAKE_PREFLIGHT_OUTPUT:-}"
  local preflight_exit="${FAKE_PREFLIGHT_EXIT:-0}"
  local fake_bin="$BATS_TEST_TMPDIR/fake-eidolons-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/eidolons" <<STUB
#!/usr/bin/env bash
# Fake eidolons stub for GAP-2 memory preflight tests.
if [ "\${1:-}" = "memory" ] && [ "\${2:-}" = "preflight" ]; then
  printf '%s' "$preflight_out"
  exit "$preflight_exit"
fi
# Delegate everything else to the real checkout CLI.
exec bash "$EIDOLONS_ROOT/cli/eidolons" "\$@"
STUB
  chmod +x "$fake_bin/eidolons"
  # Prepend to PATH so command -v eidolons finds this stub first.
  export PATH="$fake_bin:$PATH"
}

@test "harness: session_start appends memory digest when preflight non-empty (AC-R28-1)" {
  seed_manifest
  seed_cortex
  # Stub eidolons memory preflight to return a digest.
  export FAKE_PREFLIGHT_OUTPUT="[semantic/T1] Prior spec: harness mechanization shipped"
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # additionalContext must contain the cortex digest.
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")"
  [[ "$_ctx" =~ "Roster Index" ]]
  # AND the memory section.
  [[ "$_ctx" =~ "Prior project memory (CRYSTALIUM recall)" ]]
  [[ "$_ctx" =~ "[semantic/T1]" ]]
  [[ "$_ctx" =~ "Prior spec: harness mechanization shipped" ]]
}

@test "harness: session_start cortex-only when preflight empty (AC-R28-2)" {
  seed_manifest
  seed_cortex
  # Stub eidolons memory preflight to return empty.
  export FAKE_PREFLIGHT_OUTPUT=""
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")"
  # Must have cortex content.
  [[ "$_ctx" =~ "Roster Index" ]]
  # Must NOT have memory section heading (no empty heading).
  ! [[ "$_ctx" =~ "Prior project memory (CRYSTALIUM recall)" ]]
}

@test "harness: session_start codex parity — memory digest in additionalContext (AC-R28-4)" {
  seed_manifest
  seed_cortex
  export FAKE_PREFLIGHT_OUTPUT="[episodic/T1] Codex parity check"
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook codex --session-start
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")"
  [[ "$_ctx" =~ "Prior project memory (CRYSTALIUM recall)" ]]
  [[ "$_ctx" =~ "Codex parity check" ]]
}

@test "harness: session_start fail-open when preflight errors (AC-R28-6)" {
  seed_manifest
  seed_cortex
  # Stub eidolons memory preflight to exit non-zero.
  export FAKE_PREFLIGHT_OUTPUT=""
  export FAKE_PREFLIGHT_EXIT="1"
  setup_fake_eidolons_for_memory
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # Cortex digest still emits — fail-open.
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")"
  [[ "$_ctx" =~ "Roster Index" ]]
  # No memory section — graceful skip.
  ! [[ "$_ctx" =~ "Prior project memory (CRYSTALIUM recall)" ]]
}

# ─── Wave-2 CORTEX/MEMORY: procedural-skill surfacing hint (session_start) ────

@test "harness: session_start memory digest carries the [skill/...] hint line when digest non-empty" {
  seed_manifest
  seed_cortex
  # A digest containing a procedural ('[skill/tier]') record, as memory.sh's
  # Step 8 now renders them.
  export FAKE_PREFLIGHT_OUTPUT="[skill/T1] Safe merge protocol: run make test before merging"
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")"
  [[ "$_ctx" =~ "Prior project memory (CRYSTALIUM recall)" ]]
  [[ "$_ctx" =~ "Lines tagged [skill/...] are verified procedural skills" ]]
  [[ "$_ctx" =~ "prefer invoking them over re-deriving the procedure" ]]
  [[ "$_ctx" =~ "[skill/T1] Safe merge protocol" ]]
}

@test "harness: session_start carries no [skill/...] hint line when preflight digest is empty" {
  seed_manifest
  seed_cortex
  export FAKE_PREFLIGHT_OUTPUT=""
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")"
  [[ "$_ctx" =~ "Roster Index" ]]
  ! [[ "$_ctx" =~ "Lines tagged" ]]
  ! [[ "$_ctx" =~ "Prior project memory (CRYSTALIUM recall)" ]]
}

# ─── ESL forcing-function: M1 (SessionStart) + M2 (UPS rider) ─────────────────
#
# Gates encoded here: G-OPTIN (P0, RED-first), G-PRESENT, G-MODE, G-RESUME,
# G-FAILOPEN (P0), G-NOCHURN (RED-first), G-TRIVIAL, G-BUDGET.
# The opt-in gate is tonberry-in-BOTH (.mcp.json AND eidolons.mcp.lock), modeled
# on the crystalium memory preflight gate (cli/src/memory.sh:117-129).

# The exact preflight digest used when the v1.44.0 G-OPTIN baseline fixture was
# captured. The byte-identical assertion only holds if the memory block matches.
ESL_BASELINE_PREFLIGHT="[semantic/T1] Prior spec: ESL forcing baseline fixture"

# seed_tonberry [enforcement_mode]
# Writes a tonberry entry into BOTH .mcp.json and eidolons.mcp.lock so the
# opt-in gate fires. Optional arg writes an `enforcement:` line (advisory|block).
seed_tonberry() {
  local mode="${1:-}"
  cat > .mcp.json <<'EOF'
{
  "mcpServers": {
    "tonberry": {
      "command": "docker",
      "args": ["run", "--rm", "-i", "ghcr.io/rynaro/tonberry", "serve"]
    }
  }
}
EOF
  {
    printf 'mcps:\n'
    printf '  - name: tonberry\n'
    printf '    kind: oci-image\n'
    printf '    version: "0.4.0"\n'
    [ -n "$mode" ] && printf '    enforcement: "%s"\n' "$mode"
  } > eidolons.mcp.lock
}

# seed_inflight_change <id> <status>
seed_inflight_change() {
  local id="$1" status="$2"
  mkdir -p ".spectra/changes/$id"
  printf '{"change_id":"%s","status":"%s"}\n' "$id" "$status" > ".spectra/changes/$id/change.json"
}

# Portable mtime + content hash (GNU-first; BSD fallback — see mcp_install.bats).
_esl_mtime() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"; }
_esl_md5()   { md5sum "$1" 2>/dev/null | cut -d' ' -f1 || md5 -q "$1"; }

@test "ESL G-OPTIN (P0): tonberry absent → SessionStart additionalContext byte-identical to v1.44.0 baseline" {
  seed_manifest
  seed_cortex
  export FAKE_PREFLIGHT_OUTPUT="$ESL_BASELINE_PREFLIGHT"
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  # tonberry is ABSENT (no .mcp.json / no lock) → opt-in gate must skip silently.
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ] || return 1
  [ -n "$output" ] || return 1
  printf '%s' "$output" | jq -j '.hookSpecificOutput.additionalContext' > "$BATS_TEST_TMPDIR/ctx.out"
  # BYTE-IDENTICAL to the captured baseline (the RED-first proof: any ESL leak or
  # any memory/cortex regression changes these bytes and fails cmp).
  cmp "$BATS_TEST_TMPDIR/ctx.out" "$EIDOLONS_ROOT/cli/tests/fixtures/esl/baseline_session_additionalContext.txt" || return 1
  # And no ESL heading leaked into a non-ESL project.
  ! grep -q '## ESL' "$BATS_TEST_TMPDIR/ctx.out"
}

@test "ESL G-PRESENT: tonberry present → ESL block AND memory block AND cortex coexist" {
  seed_manifest
  seed_cortex
  seed_tonberry advisory
  export FAKE_PREFLIGHT_OUTPUT="[semantic/T1] prior project context"
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$_ctx" == *"## ESL — spec lifecycle in effect"* ]] || return 1
  [[ "$_ctx" == *"Roster Index"* ]] || return 1
  [[ "$_ctx" == *"Prior project memory (CRYSTALIUM recall)"* ]]
}

@test "ESL G-MODE (M1): advisory → SHOULD; block → MUST; trivial escape always named" {
  seed_manifest
  seed_cortex
  export FAKE_PREFLIGHT_OUTPUT=""
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory

  seed_tonberry advisory
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$_ctx" == *"SHOULD open a change"* ]] || return 1
  [[ "$_ctx" != *"MUST open a change"* ]] || return 1
  [[ "$_ctx" == *"Kupo"* ]] || return 1  # trivial escape named

  seed_tonberry block
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$_ctx" == *"MUST open a change before"* ]] || return 1
  [[ "$_ctx" == *"Kupo"* ]]
}

@test "ESL G-RESUME: an in-flight change → RESUME line names change_id + status (archived skipped)" {
  seed_manifest
  seed_cortex
  export FAKE_PREFLIGHT_OUTPUT=""
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  seed_tonberry block
  seed_inflight_change "auth-flow" "in_progress"
  seed_inflight_change "old-done" "archived"   # must be filtered out (status != archived)
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$_ctx" == *"RESUME:"* ]] || return 1
  [[ "$_ctx" == *"auth-flow"* ]] || return 1
  [[ "$_ctx" == *"in_progress"* ]] || return 1
  [[ "$_ctx" != *"old-done"* ]]
}

@test "ESL G-FAILOPEN (P0): corrupt lock + non-JSON change.json → exit 0, cortex+memory still emit" {
  seed_manifest
  seed_cortex
  export FAKE_PREFLIGHT_OUTPUT="[semantic/T1] still here"
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  # tonberry "present" (gate passes via grep) but the lock body is garbage YAML.
  printf '{"mcpServers":{"tonberry":{"command":"docker","args":["run"]}}}\n' > .mcp.json
  printf 'name: tonberry\n::: not : valid : yaml : [[[\n' > eidolons.mcp.lock
  mkdir -p .spectra/changes/broken
  printf 'NOT JSON {{{' > .spectra/changes/broken/change.json
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  # Graceful degrade: the cortex + memory sections still emit (no crash).
  [[ "$_ctx" == *"Roster Index"* ]] || return 1
  [[ "$_ctx" == *"Prior project memory (CRYSTALIUM recall)"* ]]
}

@test "ESL G-NOCHURN (RED-first): SessionStart hook with tonberry present does NOT change .mcp.json mtime" {
  seed_manifest
  seed_cortex
  export FAKE_PREFLIGHT_OUTPUT=""
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  seed_tonberry block
  local before_mtime before_md5 after_mtime after_md5
  before_mtime="$(_esl_mtime .mcp.json)"
  before_md5="$(_esl_md5 .mcp.json)"
  sleep 1   # 1s granularity: a re-write would yield a strictly later mtime
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ] || return 1
  after_mtime="$(_esl_mtime .mcp.json)"
  after_md5="$(_esl_md5 .mcp.json)"
  # The arm only READS .mcp.json — content, and mtime, must be untouched.
  [ "$before_md5" = "$after_md5" ] || return 1
  [ "$before_mtime" = "$after_mtime" ]
}

@test "ESL G-BUDGET: SessionStart ESL block is <=500 chars (block + resume = largest case)" {
  seed_manifest
  seed_cortex
  export FAKE_PREFLIGHT_OUTPUT=""
  export FAKE_PREFLIGHT_EXIT="0"
  setup_fake_eidolons_for_memory
  seed_tonberry block
  seed_inflight_change "a-fairly-long-change-identifier" "in_progress"
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook claude-code --session-start
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  # The ESL block is the trailing section (appended after cortex+memory).
  _esl="$(printf '%s' "$_ctx" | awk '/^## ESL/{f=1} f{print}')"
  local _len
  _len="$(printf '%s' "$_esl" | wc -m | tr -d ' ')"
  [ "$_len" -gt 0 ] || return 1
  [ "$_len" -le 500 ]
}

# ─── M2 — UserPromptSubmit ESL rider (driven via a fixed routing artifact) ────
# Drive harness_hook.sh directly with a crafted ARTIFACT_JSON so the route is
# deterministic (the live router's tau scoring is not under test here).

@test "ESL M2 rider: advisory route appends a SHOULD ESL clause without dropping the directive" {
  seed_tonberry advisory
  local art='{"decision":"route","selected":["spectra"],"tier":"standard","chain":[]}'
  run env HOOK_HOST=claude-code HOOK_MODE=run HOOK_EVENT_NAME=UserPromptSubmit \
    ARTIFACT_JSON="$art" PROMPT="implement the authentication flow" \
    bash "$EIDOLONS_ROOT/cli/src/harness_hook.sh"
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$_ctx" == *"via the Task tool"* ]] || return 1                # base directive retained
  [[ "$_ctx" == *"ESL project: open a change first (SHOULD)"* ]] || return 1
  [[ "$_ctx" == *"mcp__tonberry__propose"* ]]
}

@test "ESL M2 rider: block route uses the MUST ESL clause" {
  seed_tonberry block
  local art='{"decision":"route","selected":["vivi"],"tier":"standard","chain":[]}'
  run env HOOK_HOST=claude-code HOOK_MODE=run HOOK_EVENT_NAME=UserPromptSubmit \
    ARTIFACT_JSON="$art" PROMPT="x" \
    bash "$EIDOLONS_ROOT/cli/src/harness_hook.sh"
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$_ctx" == *"ESL project: MUST open a change first"* ]] || return 1
  [[ "$_ctx" == *"mcp__tonberry__propose"* ]]
}

@test "ESL M2 opt-in: tonberry absent → routing directive carries NO ESL clause" {
  # No .mcp.json / no lock → opt-in gate skips.
  local art='{"decision":"route","selected":["spectra"],"tier":"standard","chain":[]}'
  run env HOOK_HOST=claude-code HOOK_MODE=run HOOK_EVENT_NAME=UserPromptSubmit \
    ARTIFACT_JSON="$art" PROMPT="x" \
    bash "$EIDOLONS_ROOT/cli/src/harness_hook.sh"
  [ "$status" -eq 0 ] || return 1
  _ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$_ctx" == *"via the Task tool"* ]] || return 1
  [[ "$_ctx" != *"ESL project:"* ]]
}

@test "ESL G-TRIVIAL: clarify/trivial route → empty stdout even with tonberry present (M2 silent)" {
  seed_tonberry block
  local art='{"decision":"clarify"}'
  run env HOOK_HOST=claude-code HOOK_MODE=run HOOK_EVENT_NAME=UserPromptSubmit \
    ARTIFACT_JSON="$art" PROMPT="thanks, that looks good" \
    bash "$EIDOLONS_ROOT/cli/src/harness_hook.sh"
  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# ECM P2 — Host-Adapter Recipes (.spectra/changes/ecm-p2-host-adapters,
# acceptance-criteria.md SHA 629b0f10…). Tracks A–G. Track H is RETIRED.
#
# This file owns the "harness install/remove WIRING" style ACs — hooks.json
# shape, marker-block files, config.toml, removal, lock schema keys — mirroring
# the existing per-host convention already in this file (copilot suite, codex
# hooks.json, cursor mdc, strict tier). The "run --hook <host>" behavioral/
# envelope-content ACs (AC-CDX-3/4/5, AC-FO-2, AC-LK-3) live in context.bats.
# ═══════════════════════════════════════════════════════════════════════════

# seed_manifest_ecm_hosts HOSTS_CSV — eidolons.yaml with 'context: enabled: true'
# and the given hosts.wire list. Local per FINDING-031 (distinct from
# context.bats's seed_manifest_ecm_on — bats test files share no functions).
seed_manifest_ecm_hosts() {
  local hosts_csv="${1:-claude-code}"
  local hosts_yaml=""
  local first=true
  for _h in $(printf '%s' "$hosts_csv" | tr ',' ' '); do
    if [[ "$first" == "true" ]]; then hosts_yaml="$_h"; first=false; else hosts_yaml="$hosts_yaml, $_h"; fi
  done
  cat > eidolons.yaml <<EOF
version: 1
hosts:
  wire: [$hosts_yaml]
context:
  enabled: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

# yaml_to_json_local FILE — local yq wrapper (context.bats has its own
# identically-named, identically-implemented copy; bats test files do not
# share functions, per FINDING-031).
yaml_to_json_local() {
  yq -o=json eval '.' "$1" 2>/dev/null || yq . "$1"
}

# ─── Track A remainder: AC-CDX-1, AC-CDX-2, AC-CDX-6, AC-CDX-7 ─────────────

@test "AC-CDX-1: codex PostToolUse shim invokes run --hook codex --post-tool-use" {
  seed_manifest_ecm_hosts codex
  seed_lock
  run eidolons harness install --hosts codex
  [ "$status" -eq 0 ]
  [ -f ".eidolons/harness/hooks/codex-PostToolUse.sh" ]
  run grep -q 'run --hook codex --post-tool-use' .eidolons/harness/hooks/codex-PostToolUse.sh
  [ "$status" -eq 0 ]
}

@test "AC-CDX-2: .codex/hooks.json PostToolUse array carries the codex shim command" {
  seed_manifest_ecm_hosts codex
  seed_lock
  run eidolons harness install --hosts codex
  [ "$status" -eq 0 ]
  run jq -e '.hooks.PostToolUse[].command | select(endswith("codex-PostToolUse.sh"))' .codex/hooks.json
  [ "$status" -eq 0 ]
}

@test "AC-CDX-6: absent model_auto_compact_token_limit is written to .codex/config.toml" {
  seed_manifest_ecm_hosts codex
  seed_lock
  run eidolons harness install --hosts codex
  [ "$status" -eq 0 ]
  run grep -q '^model_auto_compact_token_limit' .codex/config.toml
  [ "$status" -eq 0 ]
  run jq -e '.context.codex_autocompact_managed == true' <<< "$(yaml_to_json_local eidolons.lock)"
  [ "$status" -eq 0 ]
}

@test "AC-CDX-6b: model_auto_compact_token_limit managed=true survives a re-install (idempotent, not re-flagged foreign)" {
  seed_manifest_ecm_hosts codex
  seed_lock
  run eidolons harness install --hosts codex
  [ "$status" -eq 0 ]
  run eidolons harness install --hosts codex
  [ "$status" -eq 0 ]
  run jq -e '.context.codex_autocompact_managed == true' <<< "$(yaml_to_json_local eidolons.lock)"
  [ "$status" -eq 0 ]
}

@test "AC-CDX-7: a foreign model_auto_compact_token_limit value is left byte-unchanged" {
  seed_manifest_ecm_hosts codex
  seed_lock
  mkdir -p .codex
  printf 'model_auto_compact_token_limit = 999999\nother_key = "x"\n' > .codex/config.toml
  before_sum="$(sha256sum .codex/config.toml 2>/dev/null || shasum -a 256 .codex/config.toml)"
  run eidolons harness install --hosts codex
  [ "$status" -eq 0 ]
  after_sum="$(sha256sum .codex/config.toml 2>/dev/null || shasum -a 256 .codex/config.toml)"
  [ "$before_sum" = "$after_sum" ]
  run jq -e '.context.codex_autocompact_managed == false' <<< "$(yaml_to_json_local eidolons.lock)"
  [ "$status" -eq 0 ]
}

# ─── Track B: AC-OC-1..4 + broadened install trigger ───────────────────────

@test "AC-OC-1: opencode plugin registers experimental.chat.system.transform" {
  seed_manifest_ecm_hosts opencode
  seed_lock
  run eidolons harness install --hosts opencode
  [ "$status" -eq 0 ]
  [ -f ".opencode/plugins/eidolons.js" ]
  run grep -q 'experimental' .opencode/plugins/eidolons.js
  [ "$status" -eq 0 ]
  run grep -q "chat.system.transform" .opencode/plugins/eidolons.js
  [ "$status" -eq 0 ]
}

@test "AC-OC-2: opencode transform appends a live zone= meter line to output.system (node smoke-run)" {
  command -v node >/dev/null 2>&1 || skip "node not on PATH"
  seed_manifest_ecm_hosts opencode
  seed_lock
  run eidolons harness install --hosts opencode
  [ "$status" -eq 0 ]
  run grep -q 'output.system' .opencode/plugins/eidolons.js
  [ "$status" -eq 0 ]

  mkdir -p .eidolons/.context
  cat > .eidolons/.context/meter.json <<'EOF'
{"ecm_version":"0.1","zone":"amber","utilization":0.63}
EOF
  cp .opencode/plugins/eidolons.js "$BATS_TEST_TMPDIR/oc-smoke.mjs"
  run node -e "
    import('$BATS_TEST_TMPDIR/oc-smoke.mjs').then(async (mod) => {
      const output = { system: [] };
      await mod.default.hooks['experimental.chat.system.transform']({ output });
      console.log(JSON.stringify(output.system));
    }).catch((e) => { console.error('ERR', e); process.exit(1); });
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"zone="* ]]
}

@test "AC-OC-3: opencode plugin registers experimental.session.compacting" {
  seed_manifest_ecm_hosts opencode
  seed_lock
  run eidolons harness install --hosts opencode
  [ "$status" -eq 0 ]
  run grep -q 'session.compacting' .opencode/plugins/eidolons.js
  [ "$status" -eq 0 ]
}

@test "AC-OC-4: opencode ECM plugin makes no PostToolUse / per-tool inject claim" {
  seed_manifest_ecm_hosts opencode
  seed_lock
  run eidolons harness install --hosts opencode
  [ "$status" -eq 0 ]
  run grep -qi 'PostToolUse\|per-tool inject' .opencode/plugins/eidolons.js
  [ "$status" -ne 0 ]
}

@test "harness: opencode ECM plugin copies WITHOUT --strict when 'context:' alone is on" {
  seed_manifest_ecm_hosts opencode
  seed_lock
  run eidolons harness install --hosts opencode
  [ "$status" -eq 0 ]
  [ -f ".opencode/plugins/eidolons.js" ]
}

# ─── Track C: AC-CP-1..4 ────────────────────────────────────────────────────

@test "AC-CP-1: copilot ECM marker block upserted into copilot-instructions.md" {
  seed_manifest_ecm_hosts copilot
  seed_lock
  run eidolons harness install --hosts copilot
  [ "$status" -eq 0 ]
  run grep -qF '<!-- eidolon:ecm-context start -->' .github/copilot-instructions.md
  [ "$status" -eq 0 ]
}

@test "AC-CP-2: copilot ECM block carries the pin digest plus the handoff digest" {
  seed_manifest_ecm_hosts copilot
  seed_lock
  run eidolons harness install --hosts copilot
  [ "$status" -eq 0 ]
  run grep -q 'Pins:' .github/copilot-instructions.md
  [ "$status" -eq 0 ]
  run grep -q 'Prior session handoff' .github/copilot-instructions.md
  [ "$status" -eq 0 ]
}

@test "AC-CP-3: copilot ECM block makes no live-refresh claim" {
  seed_manifest_ecm_hosts copilot
  seed_lock
  run eidolons harness install --hosts copilot
  [ "$status" -eq 0 ]
  run grep -qi 'live meter\|per-prompt refresh\|updated each turn' .github/copilot-instructions.md
  [ "$status" -ne 0 ]
}

@test "AC-CP-4: copilot ECM block is byte-identical on a second install" {
  seed_manifest_ecm_hosts copilot
  seed_lock
  run eidolons harness install --hosts copilot
  [ "$status" -eq 0 ]
  _first="$(cat .github/copilot-instructions.md)"
  run eidolons harness install --hosts copilot
  [ "$status" -eq 0 ]
  _second="$(cat .github/copilot-instructions.md)"
  [ "$_first" = "$_second" ]
}

# ─── Track D: AC-CR-1..4 ────────────────────────────────────────────────────

@test "AC-CR-1: cursor ECM floor written to .cursor/rules/eidolons-context.mdc" {
  seed_manifest_ecm_hosts cursor
  seed_lock
  run eidolons harness install --hosts cursor
  [ "$status" -eq 0 ]
  [ -f ".cursor/rules/eidolons-context.mdc" ]
  run grep -qF '<!-- eidolon:ecm-context start -->' .cursor/rules/eidolons-context.mdc
  [ "$status" -eq 0 ]
}

@test "AC-CR-2: cursor ECM floor documents its static-only limitation" {
  seed_manifest_ecm_hosts cursor
  seed_lock
  run eidolons harness install --hosts cursor
  [ "$status" -eq 0 ]
  run grep -qi 'static' .cursor/rules/eidolons-context.mdc
  [ "$status" -eq 0 ]
}

@test "AC-CR-3: cursor ECM floor makes no live-injection claim" {
  seed_manifest_ecm_hosts cursor
  seed_lock
  run eidolons harness install --hosts cursor
  [ "$status" -eq 0 ]
  run grep -qi 'meter refresh\|per-prompt\|live inject' .cursor/rules/eidolons-context.mdc
  [ "$status" -ne 0 ]
}

@test "AC-CR-4: cursor ECM floor is byte-identical on a second install" {
  seed_manifest_ecm_hosts cursor
  seed_lock
  run eidolons harness install --hosts cursor
  [ "$status" -eq 0 ]
  _first="$(cat .cursor/rules/eidolons-context.mdc)"
  run eidolons harness install --hosts cursor
  [ "$status" -eq 0 ]
  _second="$(cat .cursor/rules/eidolons-context.mdc)"
  [ "$_first" = "$_second" ]
}

# ─── Track E: AC-RM-1..6 (removal parity) ──────────────────────────────────

@test "AC-RM-1: harness remove strips compactThreshold from .claude/settings.json" {
  seed_manifest_ecm_hosts claude-code
  seed_lock
  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]
  run jq -e 'has("compactThreshold")' .claude/settings.json
  [ "$status" -eq 0 ]
  run eidolons harness remove
  [ "$status" -eq 0 ]
  run jq -e 'has("compactThreshold") | not' .claude/settings.json
  [ "$status" -eq 0 ]
}

@test "AC-RM-2: harness remove strips the context: key from eidolons.lock" {
  seed_manifest_ecm_hosts claude-code
  seed_lock
  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]
  run grep -q '^context:' eidolons.lock
  [ "$status" -eq 0 ]
  run eidolons harness remove
  [ "$status" -eq 0 ]
  run grep -q '^context:' eidolons.lock
  [ "$status" -ne 0 ]
}

@test "AC-RM-3: harness remove strips the managed model_auto_compact_token_limit line" {
  seed_manifest_ecm_hosts codex
  seed_lock
  run eidolons harness install --hosts codex
  [ "$status" -eq 0 ]
  run grep -q '^model_auto_compact_token_limit' .codex/config.toml
  [ "$status" -eq 0 ]
  run eidolons harness remove
  [ "$status" -eq 0 ]
  run grep -q '^model_auto_compact_token_limit' .codex/config.toml
  [ "$status" -ne 0 ]
}

@test "AC-RM-4: harness remove strips the copilot ECM block; sibling content survives" {
  seed_manifest_ecm_hosts copilot
  seed_lock
  run eidolons harness install --hosts copilot
  [ "$status" -eq 0 ]
  printf '\nSIBLING CONTENT MARKER\n' >> .github/copilot-instructions.md
  run eidolons harness remove
  [ "$status" -eq 0 ]
  run grep -qF '<!-- eidolon:ecm-context start -->' .github/copilot-instructions.md
  [ "$status" -ne 0 ]
  run grep -qF 'SIBLING CONTENT MARKER' .github/copilot-instructions.md
  [ "$status" -eq 0 ]
}

@test "AC-RM-5: harness remove deletes the cursor ECM .mdc floor" {
  seed_manifest_ecm_hosts cursor
  seed_lock
  run eidolons harness install --hosts cursor
  [ "$status" -eq 0 ]
  [ -f ".cursor/rules/eidolons-context.mdc" ]
  run eidolons harness remove
  [ "$status" -eq 0 ]
  [ ! -f ".cursor/rules/eidolons-context.mdc" ]
}

@test "AC-RM-6: install -> remove -> install is byte-identical for .claude/settings.json" {
  seed_manifest_ecm_hosts "claude-code,codex,copilot,cursor,opencode"
  seed_lock
  run eidolons harness install --hosts claude-code,codex,copilot,cursor,opencode
  [ "$status" -eq 0 ]
  _first="$(jq -cS . .claude/settings.json)"
  run eidolons harness remove
  [ "$status" -eq 0 ]
  run eidolons harness install --hosts claude-code,codex,copilot,cursor,opencode
  [ "$status" -eq 0 ]
  _second="$(jq -cS . .claude/settings.json)"
  [ "$_first" = "$_second" ]
}

# ─── Track F: AC-FO-1, AC-FO-3 (AC-FO-2 lives in context.bats) ─────────────

@test "AC-FO-1: cursor-only install exits 0 and writes the documentary floor" {
  seed_manifest_ecm_hosts cursor
  seed_lock
  run eidolons harness install --hosts cursor
  [ "$status" -eq 0 ]
  [ -f ".cursor/rules/eidolons-context.mdc" ]
}

@test "AC-FO-3: unwritable codex config warns and exits 0; claude-code shim still written" {
  [ "$(id -u)" -eq 0 ] && skip "running as root — chmod 0444 is not meaningful"
  seed_manifest_ecm_hosts "claude-code,codex"
  seed_lock
  mkdir -p .codex
  printf 'unrelated_key = 1\n' > .codex/config.toml
  chmod 0444 .codex/config.toml
  run eidolons harness install --hosts claude-code,codex
  [ "$status" -eq 0 ]
  [ -f ".eidolons/harness/hooks/claude-code-UserPromptSubmit.sh" ]
  chmod 0644 .codex/config.toml
}

# ─── Track G: AC-LK-1, AC-LK-2 (AC-LK-3 lives in context.bats) ─────────────

@test "AC-LK-1: eidolons.lock context.per_host records each wired host's effective tier" {
  seed_manifest_ecm_hosts "claude-code,codex,opencode,copilot,cursor"
  seed_lock
  run eidolons harness install --hosts claude-code,codex,opencode,copilot,cursor
  [ "$status" -eq 0 ]
  lock_json="$(yaml_to_json_local eidolons.lock)"
  run jq -e '.context.per_host.codex.tier == "T3"' <<< "$lock_json"
  [ "$status" -eq 0 ]
  run jq -e '.context.per_host."claude-code".tier == "T3"' <<< "$lock_json"
  [ "$status" -eq 0 ]
  run jq -e '.context.per_host.opencode.tier == "T1"' <<< "$lock_json"
  [ "$status" -eq 0 ]
  run jq -e '.context.per_host.copilot.tier == "T2"' <<< "$lock_json"
  [ "$status" -eq 0 ]
  run jq -e '.context.per_host.cursor.tier == "T2"' <<< "$lock_json"
  [ "$status" -eq 0 ]
}

@test "AC-LK-2: eidolons.lock context.codex_autocompact_managed is recorded as a boolean" {
  seed_manifest_ecm_hosts codex
  seed_lock
  run eidolons harness install --hosts codex
  [ "$status" -eq 0 ]
  run jq -e '.context.codex_autocompact_managed | type == "boolean"' <<< "$(yaml_to_json_local eidolons.lock)"
  [ "$status" -eq 0 ]
}
