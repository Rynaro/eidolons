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
