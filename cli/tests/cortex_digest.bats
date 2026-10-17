#!/usr/bin/env bats

load helpers

# Exercise the public sync path without network or third-party installers.
seed_digest_sync() {
  setup_fake_git_for_upgrade
  cp "$EIDOLONS_ROOT/roster/model-profiles.yaml" "$EIDOLONS_NEXUS/roster/"
  cp "$EIDOLONS_ROOT/roster/routing.yaml" "$EIDOLONS_NEXUS/roster/"
  cp "$EIDOLONS_ROOT/EIDOLONS.md" "$EIDOLONS_NEXUS/EIDOLONS.md"
  cat > eidolons.yaml <<'YAML'
version: 1
hosts:
  wire: [cursor]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
YAML
}

session_digest() {
  env HOOK_HOST=claude-code HOOK_MODE=session_start HOOK_EVENT_NAME=SessionStart \
    bash "$EIDOLONS_ROOT/cli/src/harness_hook.sh" | jq -r '.hookSpecificOutput.additionalContext'
}

@test "cortex digest: real sync with current cortex is byte-identical on repeat" {
  seed_digest_sync
  run eidolons sync --non-interactive
  [ "$status" -eq 0 ]
  cp .cursor/rules/eidolons-cortex.mdc first.mdc
  run eidolons sync --non-interactive
  [ "$status" -eq 0 ]
  cmp first.mdc .cursor/rules/eidolons-cortex.mdc
  [ "$(grep -cF '<!-- eidolon:cortex start -->' first.mdc)" -eq 1 ]
  [ "$(grep -cF '<!-- eidolon:cortex end -->' first.mdc)" -eq 1 ]
  grep -q '^## Roster$' first.mdc
  grep -q '^## Dispatch$' first.mdc
}

@test "cortex digest: SessionStart selects current always-loaded routing content" {
  mkdir -p .eidolons/cortex
  cp "$EIDOLONS_ROOT/EIDOLONS.md" .eidolons/cortex/EIDOLONS.md
  run session_digest
  [ "$status" -eq 0 ]
  [[ "$output" == '## Roster'* ]]
  [[ "$output" == *'## Dispatch'* ]]
  [[ "$output" != *'<!--'* ]]
  [[ "$output" != *'## Agent display names'* ]]
}

@test "cortex digest: legacy headings select routing sections without trailing markers" {
  mkdir -p .eidolons/cortex
  cat > .eidolons/cortex/EIDOLONS.md <<'MD'
<!-- eidolon:cortex start -->
# Old cortex
## Roster Index (always-loaded)
Legacy roster
## Other
Excluded
## Dispatch Protocol (always-loaded)
Legacy dispatch
<!-- eidolon:cortex end -->
MD
  run session_digest
  [ "$status" -eq 0 ]
  [[ "$output" == '## Roster Index'* ]]
  [[ "$output" == *'Legacy dispatch'* ]]
  [[ "$output" != *'Excluded'* ]]
  [[ "$output" != *'<!--'* ]]
}

@test "cortex digest: unknown format fallback strips all managed marker lines" {
  mkdir -p .eidolons/cortex
  cat > .eidolons/cortex/EIDOLONS.md <<'MD'
<!-- eidolon:cortex start -->
# Custom routing
Safe routing prose
<!-- eidolon:atlas start -->
Member prose
<!-- eidolon:atlas end -->
<!-- eidolon:cortex end -->
MD
  run session_digest
  [ "$status" -eq 0 ]
  [[ "$output" == '# Custom routing'* ]]
  [[ "$output" == *'Safe routing prose'* ]]
  [[ "$output" != *'<!--'* ]]
}

@test "cortex digest: sync repairs nested cursor blocks and preserves surrounding prose" {
  seed_digest_sync
  mkdir -p .cursor/rules
  cat > .cursor/rules/eidolons-cortex.mdc <<'MD'
---
alwaysApply: true
---
User preface
<!-- eidolon:cortex start -->
Old digest
<!-- eidolon:cortex start -->
Nested digest
<!-- eidolon:cortex end -->
<!-- eidolon:cortex end -->
User epilogue
MD
  run eidolons sync --non-interactive
  [ "$status" -eq 0 ]
  [ "$(grep -cF '<!-- eidolon:cortex start -->' .cursor/rules/eidolons-cortex.mdc)" -eq 1 ]
  [ "$(grep -cF '<!-- eidolon:cortex end -->' .cursor/rules/eidolons-cortex.mdc)" -eq 1 ]
  grep -q '^User preface$' .cursor/rules/eidolons-cortex.mdc
  grep -q '^User epilogue$' .cursor/rules/eidolons-cortex.mdc
  ! grep -q 'Nested digest' .cursor/rules/eidolons-cortex.mdc
  cp .cursor/rules/eidolons-cortex.mdc repaired.mdc
  run eidolons sync --non-interactive
  [ "$status" -eq 0 ]
  cmp repaired.mdc .cursor/rules/eidolons-cortex.mdc
}

@test "cortex digest: current headings work without explicit always-loaded markers" {
  mkdir -p .eidolons/cortex
  cat > .eidolons/cortex/EIDOLONS.md <<'MD'
<!-- eidolon:cortex start -->
# Preamble
## Roster
Current roster
## Dispatch
Current dispatch
## Deep tables
Excluded
<!-- eidolon:cortex end -->
MD
  run session_digest
  [ "$status" -eq 0 ]
  [[ "$output" == '## Roster'* ]]
  [[ "$output" == *'Current dispatch'* ]]
  [[ "$output" != *'Preamble'* ]]
  [[ "$output" != *'Excluded'* ]]
  [[ "$output" != *'<!--'* ]]
}

@test "cortex digest: fallback remains capped at 4000 bytes after stripping markers" {
  mkdir -p .eidolons/cortex
  {
    printf '%s\n' '<!-- eidolon:cortex start -->'
    printf '%5000s' '' | tr ' ' x
    printf '\n%s\n' '<!-- eidolon:cortex end -->'
  } > .eidolons/cortex/EIDOLONS.md
  session_digest > digest.txt
  # jq adds its own newline to the 4000-byte payload.
  [ "$(wc -c < digest.txt | tr -d ' ')" -eq 4001 ]
  ! grep -q '<!--' digest.txt
}

@test "cortex digest: sync repairs a truncated nested block without losing user epilogue" {
  seed_digest_sync
  mkdir -p .cursor/rules
  cat > .cursor/rules/eidolons-cortex.mdc <<'MD'
---
alwaysApply: true
---
User preface
<!-- eidolon:cortex start -->
<!-- eidolon:cortex start -->
Truncated digest
<!-- eidolon:cortex end -->
User epilogue
MD
  run eidolons sync --non-interactive
  [ "$status" -eq 0 ]
  [ "$(grep -cF '<!-- eidolon:cortex start -->' .cursor/rules/eidolons-cortex.mdc)" -eq 1 ]
  [ "$(grep -cF '<!-- eidolon:cortex end -->' .cursor/rules/eidolons-cortex.mdc)" -eq 1 ]
  grep -q '^User preface$' .cursor/rules/eidolons-cortex.mdc
  grep -q '^User epilogue$' .cursor/rules/eidolons-cortex.mdc
  ! grep -q 'Truncated digest' .cursor/rules/eidolons-cortex.mdc
  cp .cursor/rules/eidolons-cortex.mdc repaired.mdc
  run eidolons sync --non-interactive
  [ "$status" -eq 0 ]
  cmp repaired.mdc .cursor/rules/eidolons-cortex.mdc
}
