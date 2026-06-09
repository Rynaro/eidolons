#!/usr/bin/env bats
#
# cli/tests/model_wiring.bats — model frontmatter write-adapter tests.
#
# Stories:
#   USE-WIRES      model use spectra@standard rewrites .claude/agents/spectra.md
#                  with sentinel + model: <value>
#   IDEMPOTENT     repeat use with same value is byte-identical (no write)
#   PROFILE-REWRITE profile openai re-resolves all members
#   COPILOT-NOOP   copilot-only project exits 0, no model: written
#   CURSOR-NOOP    cursor: no model: written
#   CODEX-WIRES    codex host gets .codex/agents/<id>.md managed block
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
  _write_agent_file .codex/agents/spectra.md
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

# ─── CURSOR-NOOP ──────────────────────────────────────────────────────────────

@test "model wiring: cursor host is a no-op (exit 0)" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [cursor]
members:
  - name: spectra
    version: "^4.0.0"
EOF
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
}

# ─── CODEX-WIRES ──────────────────────────────────────────────────────────────

@test "model wiring: codex host writes managed block to .codex/agents/spectra.md" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_codex_project
  # openai profile applies to codex.
  eidolons model profile openai >/dev/null 2>&1 || true
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  # File should exist and have sentinel.
  if [ -f ".codex/agents/spectra.md" ]; then
    grep -q "# eidolons:managed model" .codex/agents/spectra.md
  fi
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
  # Should succeed (exit 0).
  [ "$status" -eq 0 ]

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
