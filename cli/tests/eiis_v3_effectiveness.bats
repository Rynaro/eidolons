#!/usr/bin/env bats

load helpers

setup_effective_package() {
  mkdir -p .eidolons/atlas/skills/locate
  cat > .eidolons/atlas/PERSONA.md <<'EOF'
# ATLAS persona
REFUSAL: never modify repository files.
HANDOFF: send implementation work to Vivi.
EOF
  printf '%s\n' '# ATLAS methodology' > .eidolons/atlas/SPEC.md
  printf '%s\n' '# Locate skill' 'Return evidence-anchored paths.' > .eidolons/atlas/skills/locate/SKILL.md
  cat > .eidolons/atlas/manifest.json <<'JSON'
{"schema_version":"3.0","eiis_version":"3.0.0","name":"atlas","version":"3.0.0","methodology":"ATLAS","entrypoints":{"persona":"PERSONA.md","spec":"SPEC.md"},"skills":{"locate":{"entrypoint":"skills/locate/SKILL.md","resources":[]}}}
JSON
  cat > .eidolons/atlas/install.receipt.json <<'JSON'
{"schema_version":"1.0","eiis_version":"3.0.0","package":{"name":"atlas","version":"3.0.0","manifest_sha256":"0000000000000000000000000000000000000000000000000000000000000000"},"installed_at":"2026-08-17T00:00:00Z","target":".eidolons/atlas","tree_sha256":"0000000000000000000000000000000000000000000000000000000000000000","adapters":[]}
JSON
}

@test "v3 effectiveness: all five hosts discover the same persona and spec" {
  setup_effective_package
  run bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters atlas claude-code,codex,copilot,cursor,opencode' _ "$EIDOLONS_ROOT"
  [ "$status" -eq 0 ]
  for file in .claude/agents/atlas.md .codex/agents/atlas.toml .github/agents/atlas.agent.md .cursor/rules/atlas.mdc .opencode/agents/atlas.md; do
    grep -q '.eidolons/atlas/PERSONA.md' "$file"
    grep -q '.eidolons/atlas/SPEC.md' "$file"
  done
}

@test "v3 effectiveness: skill content loads identically through symlink and pointer fallback" {
  setup_effective_package
  bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters atlas claude-code' _ "$EIDOLONS_ROOT"
  cmp -s .claude/skills/atlas-locate/SKILL.md .eidolons/atlas/skills/locate/SKILL.md
  rm -f .claude/skills/atlas-locate/SKILL.md
  EIDOLONS_NO_SYMLINKS=1 bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters atlas claude-code' _ "$EIDOLONS_ROOT"
  canonical="$(sed -n 's/.*Load `\([^`]*\)`.*/\1/p' .claude/skills/atlas-locate/SKILL.md | head -1)"
  [ "$canonical" = ".eidolons/atlas/skills/locate/SKILL.md" ]
  grep -q 'Return evidence-anchored paths' "$canonical"
}

@test "v3 effectiveness: adapters preserve refusal and handoff authority by reference without duplication" {
  setup_effective_package
  bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters atlas claude-code,codex' _ "$EIDOLONS_ROOT"
  grep -q 'REFUSAL:' .eidolons/atlas/PERSONA.md
  grep -q 'HANDOFF:' .eidolons/atlas/PERSONA.md
  ! grep -q 'never modify' .claude/agents/atlas.md
  ! grep -q 'send implementation' .codex/agents/atlas.toml
}

@test "v3 effectiveness: adapter rendering does not alter deterministic routing" {
  seed_manifest
  setup_effective_package
  before="$(eidolons run --json 'map the authentication flow')"
  bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters atlas claude-code,codex,copilot,cursor,opencode' _ "$EIDOLONS_ROOT"
  after="$(eidolons run --json 'map the authentication flow')"
  [ "$before" = "$after" ]
  [ "$(printf '%s' "$after" | jq -r '.selected[0]')" = "atlas" ]
}

@test "v3 effectiveness: Claude compaction reinjection remains registered" {
  seed_manifest
  seed_lock
  setup_effective_package
  run eidolons harness install --hosts claude-code --non-interactive
  [ "$status" -eq 0 ]
  matcher="$(jq -r '.hooks.SessionStart[] | select(.hooks[].command | contains("claude-code-SessionStart")) | .matcher' .claude/settings.json)"
  [ "$matcher" = 'startup|resume|clear|compact' ]
  run eidolons harness check
  [ "$status" -eq 0 ]
}
