#!/usr/bin/env bats

load helpers

@test "doctor: fails without eidolons.yaml" {
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ eidolons\.yaml\ missing ]]
}

@test "doctor: reports missing lock" {
  seed_manifest
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ eidolons\.lock\ missing ]]
}

@test "doctor: reports missing per-member install when .eidolons dir absent" {
  seed_manifest
  seed_lock
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ not\ installed ]]
}

@test "doctor: reports missing host dispatch files" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  run eidolons doctor
  # manifest wires claude-code but .claude/agents/atlas.md is absent.
  [ "$status" -ne 0 ]
  [[ "$output" =~ \.claude/agents/atlas\.md\ missing|claude-code\ declared\ but ]]
}

@test "doctor: passes on a fully wired project" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  # Per-vendor self-sufficient file satisfies the claude-code host check.
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ All\ checks\ passed ]]
}

@test "doctor -h: help prints" {
  run eidolons doctor -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ doctor ]]
}

@test "doctor: codex host passes when .codex/agents/*.md present" {
  # Write a manifest wired for codex only.
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
  seed_agent_install_manifest atlas
  mkdir -p .codex/agents
  echo "---" > .codex/agents/atlas.md
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "codex wired (.codex/agents/*.md present)" ]]
}

@test "doctor: codex host passes via AGENTS.md shared dispatch" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  seed_lock
  seed_agent_install_manifest atlas
  echo "# shared dispatch" > AGENTS.md
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "codex wired (AGENTS.md shared dispatch)" ]]
}

@test "doctor: codex host fails when no wiring surface found" {
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
  seed_agent_install_manifest atlas
  # No .codex/agents/ and no AGENTS.md — should fail.
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ "codex declared but no .codex/agents/*.md or AGENTS.md found" ]]
}
