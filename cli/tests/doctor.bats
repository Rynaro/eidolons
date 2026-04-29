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

# ─── Release integrity surface (Story 5.G) ────────────────────────────────

@test "doctor: surfaces verified release integrity from lock" {
  seed_manifest
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  cat > eidolons.lock <<'EOF'
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@deadbeef"
    commit: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    tree: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    archive_sha256: ""
    manifest_sha256: ""
    verification: "verified"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Release integrity" ]]
  [[ "$output" =~ "atlas@1.0.0 release integrity verified" ]]
}

@test "doctor: surfaces legacy compatibility entries non-fatally" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "no roster release metadata (legacy)" ]]
}

@test "doctor: flags missing release integrity as error" {
  seed_manifest
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  cat > eidolons.lock <<'EOF'
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@deadbeef"
    verification: "missing"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ "MISMATCH" ]]
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
