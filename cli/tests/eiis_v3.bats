#!/usr/bin/env bats

load helpers

setup_v3_package() {
  mkdir -p .eidolons/test/skills/verify
  printf '%s\n' '# Persona' > .eidolons/test/PERSONA.md
  printf '%s\n' '# Spec' > .eidolons/test/SPEC.md
  printf '%s\n' '# Verify' > .eidolons/test/skills/verify/SKILL.md
  cat > .eidolons/test/manifest.json <<'JSON'
{"schema_version":"3.0","eiis_version":"3.0.0","name":"test","version":"1.0.0","methodology":"TEST","entrypoints":{"persona":"PERSONA.md","spec":"SPEC.md"},"skills":{"verify":{"entrypoint":"skills/verify/SKILL.md","resources":[]}}}
JSON
  cat > .eidolons/test/install.receipt.json <<'JSON'
{"schema_version":"1.0","eiis_version":"3.0.0","package":{"name":"test","version":"1.0.0","manifest_sha256":"0000000000000000000000000000000000000000000000000000000000000000"},"installed_at":"2026-08-17T00:00:00Z","target":".eidolons/test","tree_sha256":"0000000000000000000000000000000000000000000000000000000000000000","adapters":[]}
JSON
}

@test "EIIS v3: nexus renders every host adapter from one package" {
  setup_v3_package
  run bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters test claude-code,codex,copilot,cursor,opencode' _ "$EIDOLONS_ROOT"
  [ "$status" -eq 0 ]
  [ -f .claude/agents/test.md ]
  [ -f .codex/agents/test.toml ]
  [ -f .github/agents/test.agent.md ]
  [ -f .cursor/rules/test.mdc ]
  [ -f .opencode/agents/test.md ]
  grep -q '.eidolons/test/PERSONA.md' .claude/agents/test.md
  grep -q '.eidolons/test/SPEC.md' .codex/agents/test.toml
}

@test "EIIS v3: Claude skill adapter is a resolving canonical symlink" {
  setup_v3_package
  run bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters test claude-code' _ "$EIDOLONS_ROOT"
  [ "$status" -eq 0 ]
  [ -L .claude/skills/test-verify/SKILL.md ]
  [ -e .claude/skills/test-verify/SKILL.md ]
  cmp -s .claude/skills/test-verify/SKILL.md .eidolons/test/skills/verify/SKILL.md
}

@test "EIIS v3: no-symlink mode emits a constrained discovery pointer" {
  setup_v3_package
  run env EIDOLONS_NO_SYMLINKS=1 bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters test claude-code; eiis_v3_check_pointer .claude/skills/test-verify/SKILL.md .eidolons/test/skills/verify/SKILL.md' _ "$EIDOLONS_ROOT"
  [ "$status" -eq 0 ]
  [ ! -L .claude/skills/test-verify/SKILL.md ]
}

@test "EIIS v3: receipt records disposable adapters, not package files" {
  setup_v3_package
  run bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters test claude-code,codex' _ "$EIDOLONS_ROOT"
  [ "$status" -eq 0 ]
  [ "$(jq '.adapters | length' .eidolons/test/install.receipt.json)" -eq 3 ]
  jq -e '.adapters | all(.canonical | startswith(".eidolons/test/"))' .eidolons/test/install.receipt.json
}

@test "EIIS v3: adapter rendering is byte-idempotent" {
  setup_v3_package
  run bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters test claude-code,codex; cp .eidolons/test/install.receipt.json receipt.first; eiis_v3_render_adapters test claude-code,codex; cmp -s receipt.first .eidolons/test/install.receipt.json' _ "$EIDOLONS_ROOT"
  [ "$status" -eq 0 ]
}

@test "EIIS v3: rendering removes member-scoped legacy and stale adapters" {
  setup_v3_package
  mkdir -p .codex/agents .github/instructions .claude/skills/test-removed
  printf '%s\n' duplicate > .codex/agents/test.md
  printf '%s\n' duplicate > .github/instructions/test.instructions.md
  printf '%s\n' duplicate > .claude/skills/test-removed/SKILL.md
  run bash -c '. "$1/cli/src/lib_eiis_v3.sh"; eiis_v3_render_adapters test claude-code,codex,copilot' _ "$EIDOLONS_ROOT"
  [ "$status" -eq 0 ]
  [ ! -e .codex/agents/test.md ]
  [ ! -e .github/instructions/test.instructions.md ]
  [ ! -e .claude/skills/test-removed/SKILL.md ]
  [ -e .claude/skills/test-verify/SKILL.md ]
}
