#!/usr/bin/env bats
# tests/gitignore.bats — T16, T17, T18 from §5.2.

load helpers

# Anchors: Spec §5.2 T16 (.gitignore append is idempotent)
@test "T16: install twice → .atlas/ line appears exactly once in .gitignore" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  local count
  count="$(grep -c '^\.atlas/$' .gitignore || true)"
  [ "$count" = "1" ]
}

# Anchors: Spec §5.2 T17 (.gitignore whitespace / variant tolerance)
@test "T17: existing .atlas/ with surrounding whitespace → no duplicate" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  # Pre-existing .gitignore with the entry wrapped in whitespace.
  printf "# user content\nnode_modules/\n  .atlas/  \nvendor/\n" > .gitignore

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  # Pattern in aci.sh tolerates leading/trailing whitespace; no dup added.
  run grep -c '.atlas/' .gitignore
  [ "$output" = "1" ]
}

# Anchors: Spec §5.2 T17 (tolerate trailing-slash variance per script doc)
@test "T17: existing '.atlas' (no trailing slash) → no duplicate" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  printf "node_modules/\n.atlas\nvendor/\n" > .gitignore

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  # Either the original '.atlas' or a new '.atlas/' entry — but not both.
  local total
  total="$(grep -Ec '^\s*\.atlas/?\s*$' .gitignore)"
  [ "$total" = "1" ]
}

# Anchors: Spec §5.2 T18 (.gitignore is created if absent)
@test "T18: install with no .gitignore → file created containing just .atlas/" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  [ ! -f .gitignore ]

  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ -f .gitignore ]
  # Exactly ".atlas/\n" content.
  local content
  content="$(cat .gitignore)"
  [ "$content" = ".atlas/" ]
}
