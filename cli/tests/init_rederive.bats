#!/usr/bin/env bats

load helpers

seed_rederive_manifest() {
  cat > eidolons.yaml <<'YAML'
# Keep this project configuration intact.
version: 1
hosts:
  wire: [claude-code, codex, copilot, cursor, opencode]
  shared_dispatch: false
members:
  - name: atlas
    version: "^1.14.0"
    source: github:Rynaro/ATLAS
YAML
}

manifest_json() {
  bash -c '. "$EIDOLONS_ROOT/cli/src/lib.sh"; yaml_to_json "$1"' _ "${1:-eidolons.yaml}"
}

assert_targets() {
  manifest_json | jq -e --argjson expected "$1" '.hosts.pointer_targets == $expected'
}

@test "re-derive inserts derived targets without hosts.strict and remains byte-identical" {
  seed_rederive_manifest
  cp eidolons.yaml before.yaml
  run eidolons init --re-derive --multi-pointer
  [ "$status" -eq 0 ]
  [[ "$output" == *'Updated hosts.pointer_targets'* ]]
  assert_targets '["AGENTS.md","CLAUDE.md",".github/copilot-instructions.md"]'
  sed '/^  pointer_targets:/d' eidolons.yaml > other-fields.yaml
  cmp before.yaml other-fields.yaml
  cp eidolons.yaml first.yaml
  run eidolons init --re-derive --multi-pointer
  [ "$status" -eq 0 ]
  cmp first.yaml eidolons.yaml
}

@test "re-derive persists explicit targets without hosts.strict" {
  seed_rederive_manifest
  run eidolons init --re-derive --pointer-targets=CLAUDE.md,AGENTS.md,.github/copilot-instructions.md
  [ "$status" -eq 0 ]
  assert_targets '["CLAUDE.md","AGENTS.md",".github/copilot-instructions.md"]'
}

@test "re-derive default union and no-multi-pointer persist without strict" {
  seed_rederive_manifest
  run eidolons init --re-derive
  [ "$status" -eq 0 ]
  assert_targets '["AGENTS.md","CLAUDE.md",".github/copilot-instructions.md"]'
  run eidolons init --re-derive --no-multi-pointer
  [ "$status" -eq 0 ]
  assert_targets '["AGENTS.md"]'
}

@test "re-derive only changes hosts targets and preserves unrelated strict and pointer keys" {
  seed_rederive_manifest
  cat >> eidolons.yaml <<'YAML'
custom:
  strict: false
  pointer_targets: [keep-me]
  nested:
    pointer_targets: [also-keep-me]
YAML
  cp eidolons.yaml before.yaml
  run eidolons init --re-derive --pointer-targets=AGENTS.md
  [ "$status" -eq 0 ]
  assert_targets '["AGENTS.md"]'
  manifest_json | jq -e '.custom.pointer_targets == ["keep-me"] and .custom.nested.pointer_targets == ["also-keep-me"]'
  # Remove only the inserted hosts field; everything else must be untouched.
  awk '/^members:/ { after_hosts=1 } !after_hosts && /^  pointer_targets:/ { next } { print }' eidolons.yaml > other-fields.yaml
  cmp before.yaml other-fields.yaml
}

@test "re-derive replaces block-list targets without leaving old list entries" {
  cat > eidolons.yaml <<'YAML'
version: 1
hosts:
    wire: [codex]
    pointer_targets:
      - CLAUDE.md
      - GEMINI.md
    # Preserve this comment and setting.
    shared_dispatch: true
members: []
YAML
  run eidolons init --re-derive --pointer-targets=AGENTS.md
  [ "$status" -eq 0 ]
  assert_targets '["AGENTS.md"]'
  grep -qF '# Preserve this comment and setting.' eidolons.yaml
  manifest_json | jq -e '.hosts.shared_dispatch == true and .hosts.wire == ["codex"]'
  ! grep -q 'GEMINI.md' eidolons.yaml
}

@test "re-derive empty derivation removes only hosts targets and is idempotent" {
  cat > eidolons.yaml <<'YAML'
version: 1
hosts:
  wire: []
  pointer_targets:
  - CLAUDE.md
  - GEMINI.md
  shared_dispatch: false
custom:
  pointer_targets: [keep-me]
members: []
YAML
  run eidolons init --re-derive
  [ "$status" -eq 0 ]
  manifest_json | jq -e '(.hosts | has("pointer_targets") | not) and .custom.pointer_targets == ["keep-me"]'
  cp eidolons.yaml first.yaml
  run eidolons init --re-derive
  [ "$status" -eq 0 ]
  cmp first.yaml eidolons.yaml
}

@test "re-derive inserts targets when hosts is the final manifest block" {
  cat > eidolons.yaml <<'YAML'
version: 1
members: []
hosts:
  wire: [codex]
  shared_dispatch: false
YAML
  run eidolons init --re-derive --pointer-targets=AGENTS.md
  [ "$status" -eq 0 ]
  assert_targets '["AGENTS.md"]'
}

@test "re-derive refuses unsupported inline hosts without claiming success or modifying manifest" {
  cat > eidolons.yaml <<'YAML'
version: 1
hosts: {wire: [codex], shared_dispatch: false}
members: []
YAML
  cp eidolons.yaml before.yaml
  run eidolons init --re-derive --pointer-targets=AGENTS.md
  [ "$status" -ne 0 ]
  [[ "$output" != *'Updated hosts.pointer_targets'* ]]
  cmp before.yaml eidolons.yaml
}

@test "re-derive leaves manifest unchanged when the candidate field cannot be verified" {
  cat > eidolons.yaml <<'YAML'
version: 1
hosts:
  wire: [codex]
  "pointer_targets": [CLAUDE.md]
members: []
YAML
  cp eidolons.yaml before.yaml
  run eidolons init --re-derive --pointer-targets=AGENTS.md
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not verify hosts.pointer_targets update'* ]]
  [[ "$output" != *'Updated hosts.pointer_targets'* ]]
  cmp before.yaml eidolons.yaml
  [ "$(find . -name '*.re-derive.*' | wc -l | tr -d ' ')" -eq 0 ]
}
