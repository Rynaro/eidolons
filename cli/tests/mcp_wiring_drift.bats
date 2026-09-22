#!/usr/bin/env bats
load helpers

seed_wiring() {
  seed_manifest
  cat >> eidolons.yaml <<'YAML'
mcps:
  - name: atlas-aci
YAML
  mkdir -p .claude/agents
  cat > .claude/agents/atlas.md <<'AGENT'
---
name: atlas
tools: [Read, mcp__atlas-aci__*, user_tool]
x-eidolons-mcp-wired: [atlas-aci]
---
User instructions.
AGENT
  bash -c '
    set -e
    . "$EIDOLONS_NEXUS/cli/src/lib.sh"
    . "$EIDOLONS_NEXUS/cli/src/lib_mcp.sh"
    version=$(mcp_catalogue_get_field atlas-aci .versions.pins.stable)
    digest=$(mcp_catalogue_get atlas-aci | jq -r --arg v "$version" ".versions.releases[\$v].digest")
    _mcp_oci_render_and_merge atlas-aci "$PWD" "$digest" cli/templates/mcp/atlas-aci.mcp.json.tmpl
    jq -n --arg v "$version" --arg d "$digest" "{mcps:[{name:\"atlas-aci\",kind:\"oci-image\",version:\$v,integrity:{value:\$d},hosts_wired:[\".mcp.json\",\".claude/agents/atlas.md\"]}]}" > eidolons.mcp.lock
  '
  jq '.userSetting="preserve" | .mcpServers.custom={command:"user",args:[]} | .mcpServers["atlas-aci"].env.USER_SETTING="keep"' .mcp.json > new.json
  mv new.json .mcp.json
}

@test "V4-03 T04: atlas-aci install wrapper preserves spaced path" {
  mkdir -p "$BATS_TEST_TMPDIR/fake-bin" "$TEST_PROJECT/Project With Spaces"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BATS_TEST_TMPDIR/fake-bin/docker"
  chmod +x "$BATS_TEST_TMPDIR/fake-bin/docker"
  export PATH="$BATS_TEST_TMPDIR/fake-bin:$PATH"
  export TARGET="$TEST_PROJECT/Project With Spaces"
  run bash -c '
    set -e
    . "$EIDOLONS_NEXUS/cli/src/lib.sh"; . "$EIDOLONS_NEXUS/cli/src/lib_mcp.sh"
    version=$(mcp_catalogue_get_field atlas-aci .versions.pins.stable)
    mcp_driver_oci_image_install atlas-aci "$version" --project-root "$TARGET" --force --no-pull
  '
  [ "$status" -eq 0 ]
  run jq -e --arg pin "$(id -u):$(id -g)" --arg mount "$TARGET:/repo:ro" '.mcpServers["atlas-aci"].args as $a | ($a[($a | index("--user"))+1] == $pin) and ($a | index($mount) != null)' "$TARGET/.mcp.json"
  [ "$status" -eq 0 ]
}

@test "V4-03 T04: generated UID long flag is correctly reported healthy" {
  seed_wiring
  run bash -c '. "$EIDOLONS_NEXUS/cli/src/lib.sh"; . "$EIDOLONS_NEXUS/cli/src/lib_mcp.sh"; _mcp_driver_oci_uid_bind_probes atlas-aci'
  [ "$status" -eq 0 ]
  [[ "$output" == *mcp_uid_pin*ok* ]]
  [[ "$output" != *'no -u'* ]]
}

@test "V4-03 T05: drift preview is read-only and explicit repair preserves user-owned controls" {
  seed_wiring
  jq '.mcpServers["atlas-aci"].args |= (index("--user") as $i | del(.[$i:$i+2]))' .mcp.json > new.json
  mv new.json .mcp.json
  sed 's/mcp__atlas-aci__/mcp__atlas_aci__/' .claude/agents/atlas.md > new.md
  mv new.md .claude/agents/atlas.md
  cp .mcp.json before.json
  cp .claude/agents/atlas.md before.md
  cp eidolons.mcp.lock before.lock
  run eidolons mcp sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *runtime*drift* ]]
  [[ "$output" == *grant*drift* ]]
  cmp .mcp.json before.json
  cmp .claude/agents/atlas.md before.md
  cmp eidolons.mcp.lock before.lock
  run eidolons mcp verify atlas-aci --json
  [ "$status" -eq 1 ]
  [[ "$output" == *V-OCI-CONFIG-DRIFT* ]]
  run eidolons mcp sync --repair-wiring
  [ "$status" -eq 0 ]
  run jq -e --arg pin "$(id -u):$(id -g)" '.userSetting=="preserve" and .mcpServers.custom.command=="user" and .mcpServers["atlas-aci"].env.USER_SETTING=="keep" and (.mcpServers["atlas-aci"].args as $a | $a[($a | index("--user"))+1] == $pin)' .mcp.json
  [ "$status" -eq 0 ]
  grep -q 'Read, mcp__atlas-aci__\*, user_tool' .claude/agents/atlas.md
  ! grep -q mcp__atlas_aci__ .claude/agents/atlas.md
  grep -q 'User instructions.' .claude/agents/atlas.md
  cp .mcp.json repaired.json
  cp .claude/agents/atlas.md repaired.md
  run eidolons mcp sync --repair-wiring
  [ "$status" -eq 0 ]
  cmp .mcp.json repaired.json
  cmp .claude/agents/atlas.md repaired.md
  run eidolons mcp verify atlas-aci --json
  [ "$status" -eq 0 ]
}

@test "V4-03 T05: explicit repair leaves an unreceipted legacy user grant alone" {
  seed_wiring
  sed '/x-eidolons-mcp-wired:/d; s/mcp__atlas-aci__/mcp__atlas_aci__/' .claude/agents/atlas.md > new.md
  mv new.md .claude/agents/atlas.md
  cp .claude/agents/atlas.md user.md
  run eidolons mcp sync --repair-wiring
  [ "$status" -eq 0 ]
  cmp user.md .claude/agents/atlas.md
}

@test "V4-03 T04: identity mounts with spaces and invoking UID survive repeated generic rendering" {
  export TARGET="$TEST_PROJECT/Project With Spaces"
  mkdir -p "$TARGET"
  run bash -c '
    set -e
    . "$EIDOLONS_NEXUS/cli/src/lib.sh"; . "$EIDOLONS_NEXUS/cli/src/lib_mcp.sh"
    for name in tonberry atomos; do
      version=$(mcp_catalogue_get_field "$name" .versions.pins.stable)
      digest=$(mcp_catalogue_get "$name" | jq -r --arg v "$version" ".versions.releases[\$v].digest")
      _mcp_oci_render_and_merge "$name" "$TARGET" "$digest" "cli/templates/mcp/$name.mcp.json.tmpl"
      cp "$TARGET/.mcp.json" "$TARGET/before.json"
      _mcp_oci_render_and_merge "$name" "$TARGET" "$digest" "cli/templates/mcp/$name.mcp.json.tmpl"
      cmp "$TARGET/before.json" "$TARGET/.mcp.json"
      jq -e --arg n "$name" --arg mount "$TARGET:$TARGET:z" --arg uid "$(id -u):$(id -g)" '\''.mcpServers[$n].args as $a | ($a | index($mount) != null) and ($a[($a | index("--user"))+1] == $uid)'\'' "$TARGET/.mcp.json"
    done
  '
  [ "$status" -eq 0 ]
}

@test "V4-03 T05: local unpublished OCI identity survives UID repair" {
  seed_wiring
  export LOCAL_DIGEST="sha256:$(printf 'ab%.0s' {1..32})"
  jq --arg d "$LOCAL_DIGEST" '.mcps[0].integrity.value=$d' eidolons.mcp.lock > new.json
  mv new.json eidolons.mcp.lock
  jq --arg d "$LOCAL_DIGEST" '.mcpServers["atlas-aci"].args |= map(if startswith("ghcr.io/rynaro/atlas-aci@") then "ghcr.io/rynaro/atlas-aci@"+$d else . end)' .mcp.json > new.json
  mv new.json .mcp.json
  run eidolons mcp verify atlas-aci --json
  [ "$status" -eq 0 ]
  [[ "$output" == *V-LOCK-UNPUBLISHED-DIGEST* ]]
  jq '.mcpServers["atlas-aci"].args |= (index("--user") as $i | del(.[$i:$i+2]))' .mcp.json > new.json
  mv new.json .mcp.json
  cp eidolons.mcp.lock local.lock
  run eidolons mcp sync --repair-wiring
  [ "$status" -eq 0 ]
  cmp local.lock eidolons.mcp.lock
  grep -q "$LOCAL_DIGEST" .mcp.json
  run eidolons mcp verify atlas-aci --json
  [ "$status" -eq 0 ]
}

@test "V4-03 T05: explicit resource repair updates declared hosts and receipt while preserving user settings" {
  seed_wiring
  # Add all supported projections and an explicit resource-profile change.
  sed 's/\[claude-code\]/[claude-code, cursor, codex, opencode]/' eidolons.yaml > new.yaml
  mv new.yaml eidolons.yaml
  mkdir -p .cursor .codex
  printf '{"custom":"cursor"}\n' > .cursor/mcp.json
  printf '{"custom":"opencode","mcp":{"atlas-aci":{"enabled":false}}}\n' > opencode.json
  printf '# user settings\nmodel = "user-model"\n' > .codex/config.toml
  cat >> eidolons.yaml <<'YAML'
    resource_profile: minimal
YAML
  run eidolons mcp sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'.codex/config.toml'* ]]
  grep -q user-model .codex/config.toml
  run eidolons mcp sync --repair-wiring
  [ "$status" -eq 0 ]
  run jq -e '.custom=="cursor" and (.mcpServers["atlas-aci"].args | index("--cpus") != null)' .cursor/mcp.json
  [ "$status" -eq 0 ]
  run jq -e '.custom=="opencode" and (.mcp["atlas-aci"].enabled==false) and (.mcp["atlas-aci"].command | index("--cpus") != null)' opencode.json
  [ "$status" -eq 0 ]
  grep -q -- '--cpus' .codex/config.toml
  grep -q 'model = "user-model"' .codex/config.toml
  run bash -c '. "$EIDOLONS_NEXUS/cli/src/lib.sh"; . "$EIDOLONS_NEXUS/cli/src/lib_mcp.sh"; _mcp_runtime_is_current atlas-aci "$PWD"'
  [ "$status" -eq 0 ]
  cp .codex/config.toml repaired.toml
  cp eidolons.mcp.lock repaired.lock
  run eidolons mcp sync --repair-wiring
  [ "$status" -eq 0 ]
  cmp repaired.toml .codex/config.toml
  cmp repaired.lock eidolons.mcp.lock
}

@test "V4-03 T05: Codex scoped repair preserves user env timeout other servers and unowned tables" {
  seed_wiring
  sed 's/\[claude-code\]/[claude-code, codex]/' eidolons.yaml > new.yaml
  mv new.yaml eidolons.yaml
  mkdir -p .codex
  cat > .codex/config.toml <<'TOML'
model = "user-model"
# eidolon:mcp start
[mcp_servers.atlas-aci]
command = "docker"
args = ["stale"]
env = { USER_SETTING = "keep" }
startup_timeout_sec = 77
[mcp_servers.other]
command = "mine"
args = []
# eidolon:mcp end
[profiles.user]
model = "other-user-model"
TOML
  run eidolons mcp sync --repair-wiring
  [ "$status" -eq 0 ]
  python3 - <<'PY'
import tomllib
p=tomllib.load(open('.codex/config.toml','rb'))
assert p['mcp_servers']['atlas-aci']['env']['USER_SETTING']=='keep'
assert p['mcp_servers']['atlas-aci']['startup_timeout_sec']==77
assert p['mcp_servers']['other']=={'command':'mine','args':[]}
assert p['profiles']['user']['model']=='other-user-model'
PY
  cp .codex/config.toml repaired.toml
  run eidolons mcp sync --repair-wiring
  [ "$status" -eq 0 ]
  cmp repaired.toml .codex/config.toml
  sed '/# eidolon:mcp/d; s/command = "docker"/command = "user-owned"/; s/"command" = "docker"/"command" = "user-owned"/' .codex/config.toml > user.toml
  cp user.toml .codex/config.toml
  run eidolons mcp sync --repair-wiring
  [ "$status" -ne 0 ]
  cmp user.toml .codex/config.toml
}
