#!/usr/bin/env bats
# Regression anchors for issue #640: a mixed-host project must never claim a
# managed Codex child while leaving model/effort to parent inheritance.
load helpers

_model_mixed_fixture() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code, codex, cursor]
members:
  - name: atlas
    version: "^1.0.0"
  - name: ramza
    version: "^1.0.0"
models:
  hosts:
    claude-code:
      profile: anthropic
    codex:
      profile: openai
      calibration:
        light: gpt-6-luna
        standard: gpt-6-sol
        deep: gpt-6-astra
    cursor:
      profile: cursor
  codex:
    unnamed_subagents:
      model: gpt-6-luna
      reasoning_effort: low
      max_concurrent_threads_per_session: 1
EOF
  cat > eidolons.lock <<'EOF'
members:
  - name: atlas
    version: 1.0.0
  - name: ramza
    version: 1.0.0
EOF
  mkdir -p .claude/agents .codex/agents .cursor/agents
  local id
  for id in atlas ramza; do
    printf '%s\n' '---' "name: $id" '---' > ".claude/agents/$id.md"
    printf '%s\n' '---' "name: $id" '---' > ".cursor/agents/$id.md"
    printf 'name = "%s"\n' "$id" > ".codex/agents/$id.toml"
  done
}

_model_wire_all() {
  . "$EIDOLONS_ROOT/cli/src/lib.sh"
  . "$EIDOLONS_ROOT/cli/src/lib_model_resolve.sh"
  . "$EIDOLONS_ROOT/cli/src/lib_model_wiring.sh"
  model_resolve_init
  model_wiring_apply_all 0 && model_wiring_update_lock_all
}

@test "issue 640: global Cursor profile fails for mixed hosts before any descriptor write" {
  _model_mixed_fixture
  yq -i '.models = {"profile":"cursor-native"}' eidolons.yaml
  local before
  before="$(cat .codex/agents/atlas.toml)"
  run _model_wire_all
  [ "$status" -ne 0 ]
  [ "$(cat .codex/agents/atlas.toml)" = "$before" ]
  ! grep -q 'eidolons:managed' .claude/agents/atlas.md
}

@test "issue 640: host profiles pin each child including Codex model and effort" {
  _model_mixed_fixture
  run _model_wire_all
  [ "$status" -eq 0 ]
  grep -q '^model = "gpt-6-sol"$' .codex/agents/atlas.toml
  grep -q '^model_reasoning_effort = "medium"$' .codex/agents/atlas.toml
  grep -q '^model = "gpt-6-astra"$' .codex/agents/ramza.toml
  grep -q '^model_reasoning_effort = "medium"$' .codex/agents/ramza.toml
  grep -q '^default_subagent_model = "gpt-6-luna"$' .codex/config.toml
  grep -q '^default_subagent_reasoning_effort = "low"$' .codex/config.toml
  [ "$(yq '.members[] | select(.name == "atlas") | .model.hosts.codex.effective_model' eidolons.lock)" = "gpt-6-sol" ]
  [ "$(yq '.members[] | select(.name == "atlas") | .model.hosts."claude-code".effective_model' eidolons.lock)" = "sonnet" ]
}

@test "issue 640: absent unnamed policy pins conservative light child under expensive parent" {
  _model_mixed_fixture
  yq -i 'del(.models.codex)' eidolons.yaml
  cat > .codex/config.toml <<'EOF'
model = "gpt-6-astra"
model_reasoning_effort = "high"
EOF
  run _model_wire_all
  [ "$status" -eq 0 ]
  grep -q '^model = "gpt-6-astra"$' .codex/config.toml
  grep -q '^default_subagent_model = "gpt-6-luna"$' .codex/config.toml
  grep -q '^default_subagent_reasoning_effort = "low"$' .codex/config.toml
}

@test "issue 640: explicit unnamed inheritance removes owned fallback pins" {
  _model_mixed_fixture
  yq -i 'del(.models.codex)' eidolons.yaml
  _model_wire_all >/dev/null
  yq -i '.models.codex.unnamed_subagents = {"inherit": true}' eidolons.yaml
  unset CONSUMER_JSON
  run _model_wire_all
  [ "$status" -eq 0 ]
  ! grep -q '^default_subagent_model = ' .codex/config.toml
  ! grep -q '^default_subagent_reasoning_effort = ' .codex/config.toml
}

@test "issue 640: model show --host codex reports Codex profile and effort" {
  _model_mixed_fixture
  run eidolons model show atlas --host codex --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.effective_model == "gpt-6-sol" and .hosts.codex.reasoning_effort == "medium"' >/dev/null
}

@test "issue 640: incompatible CLI profile leaves manifest and descriptors unchanged" {
  _model_mixed_fixture
  yq -i 'del(.models.hosts)' eidolons.yaml
  local before
  before="$(cat eidolons.yaml)"
  run eidolons model profile cursor-native
  [ "$status" -ne 0 ]
  [ "$(cat eidolons.yaml)" = "$before" ]
  ! grep -q 'eidolons:managed' .codex/agents/atlas.toml
}

@test "issue 640: unmanaged Codex effort blocks all member writes" {
  _model_mixed_fixture
  printf 'model_reasoning_effort = "high"\n' >> .codex/agents/ramza.toml
  run _model_wire_all
  [ "$status" -ne 0 ]
  ! grep -q 'eidolons:managed' .codex/agents/atlas.toml
  ! grep -q 'eidolons:managed' .claude/agents/atlas.md
}

@test "issue 640: managed false removes owned Codex pins and records unmanaged" {
  _model_mixed_fixture
  _model_wire_all >/dev/null
  yq -i '.models.hosts.codex.managed = false' eidolons.yaml
  unset CONSUMER_JSON
  _model_wire_all >/dev/null
  ! grep -q '^model = ' .codex/agents/atlas.toml
  ! grep -q '^model_reasoning_effort = ' .codex/agents/atlas.toml
  [ "$(yq '.members[] | select(.name == "atlas") | .model.hosts.codex.status' eidolons.lock)" = "unmanaged" ]
}

@test "issue 640: managed false removes owned Claude and Cursor model pins" {
  _model_mixed_fixture
  _model_wire_all >/dev/null
  yq -i '.models.hosts."claude-code".managed = false | .models.hosts.cursor.managed = false' eidolons.yaml
  unset CONSUMER_JSON
  run _model_wire_all
  [ "$status" -eq 0 ]
  ! grep -q '^model:' .claude/agents/atlas.md
  ! grep -q '^model:' .cursor/agents/atlas.md
  [ "$(yq '.members[] | select(.name == "atlas") | .model.hosts."claude-code".status' eidolons.lock)" = "unmanaged" ]
  [ "$(yq '.members[] | select(.name == "atlas") | .model.hosts.cursor.status' eidolons.lock)" = "unmanaged" ]
}

@test "issue 640: second wire is byte idempotent" {
  _model_mixed_fixture
  _model_wire_all >/dev/null
  local before
  before="$(cat .codex/agents/atlas.toml .codex/config.toml eidolons.lock)"
  _model_wire_all >/dev/null
  [ "$(cat .codex/agents/atlas.toml .codex/config.toml eidolons.lock)" = "$before" ]
}
