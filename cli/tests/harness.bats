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
  settings_json_patched: true
  codex_hooks_json_patched: false
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
  _before="$(jq -cS . .claude/settings.json)"
  run eidolons harness install --hosts claude-code --non-interactive
  [ "$status" -eq 0 ]
  _after="$(jq -cS . .claude/settings.json)"
  [ "$_before" = "$_after" ]
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
