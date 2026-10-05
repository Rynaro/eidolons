#!/usr/bin/env bats
#
# cli/tests/model_wiring.bats — host-native model descriptor write-adapter tests.
#
# Stories:
#   USE-WIRES      model use spectra@standard rewrites .claude/agents/spectra.md
#                  with sentinel + model: <value>
#   IDEMPOTENT     repeat use with same value is byte-identical (no write)
#   PROFILE-REWRITE profile openai re-resolves all members
#   COPILOT-NOOP   copilot-only project exits 0, no model: written
#   CURSOR-WIRES   cursor host gets .cursor/agents/<id>.md managed model:
#   CURSOR-NATIVE  cursor-native wires composer-2.5[] / grok-4.5 / grok-4.6
#   CODEX-WIRES    codex host gets .codex/agents/<id>.toml managed assignment
#   DRIFT-PRESERVE sync-time preserves hand-authored model: (warn)
#   DRIFT-CLOBBER  explicit use clobbers hand-authored model:
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

_write_agent_file() {
  local path="$1"
  local model_line="${2:-}"
  mkdir -p "$(dirname "$path")"
  if [ -n "$model_line" ]; then
    cat > "$path" <<EOF
---
name: spectra
description: Test agent
${model_line}
---

Body text here.
EOF
  else
    cat > "$path" <<'EOF'
---
name: spectra
description: Test agent
---

Body text here.
EOF
  fi
}

_write_agent_file_with_managed() {
  local path="$1"
  local model_val="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
name: spectra
description: Test agent
# eidolons:managed model
model: ${model_val}
---

Body text here.
EOF
}

setup_claude_code_project() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: spectra
    version: "^4.0.0"
EOF
  mkdir -p .claude/agents
  _write_agent_file .claude/agents/spectra.md
}

setup_codex_project() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
members:
  - name: spectra
    version: "^4.0.0"
EOF
  mkdir -p .codex/agents
  cat > .codex/agents/spectra.toml <<'EOF'
name = "spectra"
description = "Test agent"
developer_instructions = "Body text here."
EOF
}

# ─── USE-WIRES ────────────────────────────────────────────────────────────────

@test "model wiring: use spectra@standard writes model: to .claude/agents/spectra.md" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_claude_code_project
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  [ -f ".claude/agents/spectra.md" ]
  # File should contain the sentinel.
  grep -q "# eidolons:managed model" .claude/agents/spectra.md
}

@test "model wiring: sentinel is followed by model: line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_claude_code_project
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  # The line after the sentinel must be model: <something>.
  local model_line
  model_line="$(awk '/^# eidolons:managed model/{getline; print}' .claude/agents/spectra.md)"
  [[ "$model_line" =~ "model:" ]]
}

@test "model wiring: model: value matches resolved effective model" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_claude_code_project
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  local file_model
  file_model="$(awk '/^# eidolons:managed model/{getline; sub(/^model: /,""); print}' .claude/agents/spectra.md)"
  # spectra@standard with anthropic profile → should be the standard tier model string.
  [ -n "$file_model" ]
}

# ─── IDEMPOTENT ───────────────────────────────────────────────────────────────

@test "model wiring: repeat use same value is byte-identical" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_claude_code_project
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  local before
  before="$(cat .claude/agents/spectra.md)"
  # Second run — same value.
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  local after
  after="$(cat .claude/agents/spectra.md)"
  [ "$before" = "$after" ]
}

@test "model wiring: model: written inside frontmatter only (body unchanged)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_claude_code_project
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  # Body text must still be present.
  grep -q "Body text here" .claude/agents/spectra.md
}

# ─── COPILOT-NOOP ─────────────────────────────────────────────────────────────

@test "model wiring: copilot-only project is a no-op (exit 0)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [copilot]
members:
  - name: spectra
    version: "^4.0.0"
EOF
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  # No .claude/agents/spectra.md should be written.
  [ ! -f ".claude/agents/spectra.md" ] || ! grep -q "eidolons:managed" .claude/agents/spectra.md 2>/dev/null
}

# ─── CURSOR-WIRES ─────────────────────────────────────────────────────────────

setup_cursor_project() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [cursor]
members:
  - name: spectra
    version: "^4.0.0"
EOF
  mkdir -p .cursor/agents
  _write_agent_file .cursor/agents/spectra.md
}

@test "model wiring: cursor host writes model: to .cursor/agents/spectra.md" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor
EOF
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  [ -f ".cursor/agents/spectra.md" ]
  grep -q "# eidolons:managed model" .cursor/agents/spectra.md
}

@test "model wiring: cursor sentinel is followed by model: line" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor
EOF
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  local model_line
  model_line="$(awk '/^# eidolons:managed model/{getline; print}' .cursor/agents/spectra.md)"
  [[ "$model_line" =~ "model:" ]]
}

@test "model wiring: cursor profile resolves to cursor-profile tier models" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor
EOF
  eidolons model use spectra@deep >/dev/null 2>&1 || true
  local file_model
  file_model="$(awk '/^# eidolons:managed model/{getline; sub(/^model: /,""); print}' .cursor/agents/spectra.md)"
  # cursor profile deep tier should resolve to claude-fable-5-1 (checked against Cursor model catalog 2026-09-28)
  [ "$file_model" = "claude-fable-5-1" ]
}

@test "model wiring: cursor selects its compatible profile when models is absent" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_resolve_init; model_wiring_apply_for_member spectra 0"
  [ "$status" -eq 0 ]
  # Without explicit profile, cursor host should auto-select cursor profile
  # and resolve to deep tier (spectra default) = claude-fable-5-1 (checked against Cursor model catalog 2026-09-28)
  grep -q '^model: claude-fable-5-1$' .cursor/agents/spectra.md
}

@test "model wiring: cursor write is byte-idempotent" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor
EOF
  eidolons model use spectra@deep >/dev/null 2>&1
  local before after
  before="$(cat .cursor/agents/spectra.md)"
  eidolons model use spectra@deep >/dev/null 2>&1
  after="$(cat .cursor/agents/spectra.md)"
  [ "$before" = "$after" ]
}

@test "model wiring: cursor profile change re-resolves model" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor
EOF
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  local model_before
  model_before="$(awk '/^# eidolons:managed model/{getline; sub(/^model: /,""); print}' .cursor/agents/spectra.md)"
  # cursor standard tier = composer-2.5 (checked against Cursor model catalog 2026-09-28)
  [ "$model_before" = "composer-2.5" ]
  # Change tier
  eidolons model use spectra@light >/dev/null 2>&1 || true
  local model_after
  model_after="$(awk '/^# eidolons:managed model/{getline; sub(/^model: /,""); print}' .cursor/agents/spectra.md)"
  # cursor light tier = gemini-3.8-flash (checked against Cursor model catalog 2026-09-28)
  [ "$model_after" = "gemini-3.8-flash" ]
}

@test "model wiring: cursor sync preserves hand-authored model: (no sentinel)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor
EOF
  _write_agent_file .cursor/agents/spectra.md "model: user-authored-cursor-model"
  local before
  before="$(cat .cursor/agents/spectra.md)"
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_resolve_init; model_wiring_apply_for_member spectra 0"
  [ "$status" -ne 0 ]
  local after
  after="$(cat .cursor/agents/spectra.md)"
  [ "$before" = "$after" ]
}

@test "model wiring: cursor explicit use clobbers hand-authored model:" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor
EOF
  _write_agent_file .cursor/agents/spectra.md "model: user-authored-cursor-model"
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  grep -q "# eidolons:managed model" .cursor/agents/spectra.md
  ! grep -q "user-authored-cursor-model" .cursor/agents/spectra.md
}

@test "model wiring: cursor reset + re-sync rewrites model with default tier" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor
EOF
  # Set model first
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  grep -q "# eidolons:managed model" .cursor/agents/spectra.md
  # Reset clears per-member tier override
  run eidolons model reset spectra
  [ "$status" -eq 0 ]
  # Re-sync with default tier (from roster) should still write a model
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_resolve_init; model_wiring_apply_for_member spectra 0"
  [ "$status" -eq 0 ]
  grep -q "# eidolons:managed model" .cursor/agents/spectra.md
}

@test "model wiring: cursor-native wires Composer and Grok IDs including bracketed light" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_cursor_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: cursor-native
EOF
  eidolons model use spectra@light >/dev/null 2>&1
  local light
  light="$(awk '/^# eidolons:managed model/{getline; sub(/^model: /,""); print}' .cursor/agents/spectra.md)"
  [ "$light" = "composer-2.5[]" ]
  grep -qF 'model: composer-2.5[]' .cursor/agents/spectra.md

  eidolons model use spectra@standard >/dev/null 2>&1
  local standard
  standard="$(awk '/^# eidolons:managed model/{getline; sub(/^model: /,""); print}' .cursor/agents/spectra.md)"
  [ "$standard" = "grok-4.5" ]

  eidolons model use spectra@deep >/dev/null 2>&1
  local deep
  deep="$(awk '/^# eidolons:managed model/{getline; sub(/^model: /,""); print}' .cursor/agents/spectra.md)"
  [ "$deep" = "grok-4.6" ]
}

# ─── CODEX-WIRES ──────────────────────────────────────────────────────────────

@test "model wiring: codex host writes quoted top-level model to .codex/agents/spectra.toml" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  # openai profile applies to codex.
  eidolons model profile openai >/dev/null 2>&1 || true
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  [ -f ".codex/agents/spectra.toml" ]
  grep -q "# eidolons:managed model" .codex/agents/spectra.toml
  grep -q '^model = "gpt-5.6-terra"$' .codex/agents/spectra.toml
  grep -q '^model_reasoning_effort = "medium"$' .codex/agents/spectra.toml
}

@test "model wiring: Codex selects its compatible profile when models is absent" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_resolve_init; model_wiring_apply_for_member spectra 0"
  [ "$status" -eq 0 ]
  grep -q '^model = "gpt-5.6-sol"$' .codex/agents/spectra.toml
}

@test "model wiring: explicit Codex model pin is applied despite default profile" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  cat >> eidolons.yaml <<'EOF'
models:
  members:
    spectra:
      model: "pinned-codex-model"
EOF
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_resolve_init; model_wiring_apply_for_member spectra 0"
  [ "$status" -eq 0 ]
  grep -q '^model = "pinned-codex-model"$' .codex/agents/spectra.toml
}

@test "model wiring: codex TOML write is byte-idempotent" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  eidolons model profile openai >/dev/null 2>&1
  eidolons model use spectra@deep >/dev/null 2>&1
  local before after
  before="$(cat .codex/agents/spectra.toml)"
  eidolons model use spectra@deep >/dev/null 2>&1
  after="$(cat .codex/agents/spectra.toml)"
  [ "$before" = "$after" ]
  [ "$(grep -c '^model = ' .codex/agents/spectra.toml)" -eq 1 ]
}

@test "model wiring: codex sync preserves an unmanaged top-level model" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: openai
EOF
  printf '\nmodel = "user-owned"\n' >> .codex/agents/spectra.toml
  local before after
  before="$(cat .codex/agents/spectra.toml)"
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_resolve_init; model_wiring_apply_for_member spectra 0"
  [ "$status" -ne 0 ]
  after="$(cat .codex/agents/spectra.toml)"
  [ "$before" = "$after" ]
}

@test "model wiring: explicit codex use adopts an unmanaged top-level model" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  eidolons model profile openai >/dev/null 2>&1
  printf '\nmodel = "user-owned"\n' >> .codex/agents/spectra.toml
  run eidolons model use spectra@light
  [ "$status" -eq 0 ]
  ! grep -q 'user-owned' .codex/agents/spectra.toml
  grep -q '^model = "gpt-5.6-luna"$' .codex/agents/spectra.toml
  [ "$(grep -c '^# eidolons:managed model$' .codex/agents/spectra.toml)" -eq 1 ]
}

@test "model wiring: TOML model inside a table is not treated as top-level ownership" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  cat >> .codex/agents/spectra.toml <<'EOF'

[metadata]
model = "descriptive-only"
EOF
  eidolons model profile openai >/dev/null 2>&1
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  grep -q '^model = "descriptive-only"$' .codex/agents/spectra.toml
  [ "$(grep -c '^model = "gpt-5.6-terra"$' .codex/agents/spectra.toml)" -eq 1 ]
}

@test "model wiring: Codex TOML quotes and backslashes round-trip safely" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_wiring_patch_agent_file codex .codex/agents/spectra.toml 'model\"with\\path' 1; [ \"\$(_model_wiring_read_managed .codex/agents/spectra.toml)\" = 'model\"with\\path' ]"
  [ "$status" -eq 0 ]
  grep -Fq 'model = "model\"with\\path"' .codex/agents/spectra.toml
}

@test "model wiring: explicit same-model use normalizes a duplicate top-level TOML key" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: openai
EOF
  cat >> .codex/agents/spectra.toml <<'EOF'
# eidolons:managed model
model = "gpt-5.6-terra"
model = "user-owned-duplicate"
EOF
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  [ "$(grep -c '^model = ' .codex/agents/spectra.toml)" -eq 1 ]
  grep -q '^model = "gpt-5.6-terra"$' .codex/agents/spectra.toml
  ! grep -q 'user-owned-duplicate' .codex/agents/spectra.toml
}

@test "model wiring: passive sync preserves and warns on duplicate top-level TOML keys" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  cat >> eidolons.yaml <<'EOF'
models:
  profile: openai
EOF
  cat >> .codex/agents/spectra.toml <<'EOF'
# eidolons:managed model
model = "gpt-5.6-terra"
model = "user-owned-duplicate"
EOF
  local before after
  before="$(cat .codex/agents/spectra.toml)"
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_resolve_init; model_wiring_apply_for_member spectra 0"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "hand-authored model" ]]
  after="$(cat .codex/agents/spectra.toml)"
  [ "$before" = "$after" ]
}

# ─── DRIFT-PRESERVE ───────────────────────────────────────────────────────────

@test "model wiring: sync preserves hand-authored model: (no sentinel)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
models:
  profile: anthropic
members:
  - name: spectra
    version: "^4.0.0"
EOF
  mkdir -p .claude/agents
  # Write a hand-authored model: line (no sentinel).
  _write_agent_file .claude/agents/spectra.md "model: my-hand-authored-model"

  local before
  before="$(cat .claude/agents/spectra.md)"

  # Source libs and call sync-time wiring (warn-and-preserve mode).
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh'; . '$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh'; model_resolve_init; model_wiring_apply_for_member spectra 0"
  # The collision is surfaced as an actionable sync error.
  [ "$status" -ne 0 ]

  local after
  after="$(cat .claude/agents/spectra.md)"
  # File must be unchanged (hand-authored preserved).
  [ "$before" = "$after" ]
}

# ─── DRIFT-CLOBBER ────────────────────────────────────────────────────────────

@test "model wiring: explicit use clobbers hand-authored model:" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_claude_code_project
  # Write a hand-authored model: line.
  _write_agent_file .claude/agents/spectra.md "model: my-hand-authored-model"
  # Explicit model use → clobber mode.
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  # File should now have the sentinel (managed).
  grep -q "# eidolons:managed model" .claude/agents/spectra.md
  # Old hand-authored value should be gone.
  ! grep -q "my-hand-authored-model" .claude/agents/spectra.md
}

@test "model wiring: managed drift — existing managed value replaced on explicit use" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_claude_code_project
  # Write a managed block with an old value.
  _write_agent_file_with_managed .claude/agents/spectra.md "old-model-value"
  # Explicit use with different value.
  run eidolons model use spectra@deep
  [ "$status" -eq 0 ]
  # Sentinel must still be present.
  grep -q "# eidolons:managed model" .claude/agents/spectra.md
  # old-model-value must be gone.
  ! grep -q "old-model-value" .claude/agents/spectra.md
}
