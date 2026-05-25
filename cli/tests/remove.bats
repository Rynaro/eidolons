#!/usr/bin/env bats

load helpers

@test "remove: prints stub message and exits non-zero" {
  run eidolons remove atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ not\ yet\ implemented ]]
  [[ "$output" =~ Workaround ]]
}

@test "remove: rm alias dispatches to same stub" {
  run eidolons rm atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ not\ yet\ implemented ]]
}

# ─── G-A1.3: dispatch-pointer removed on last-Eidolon removal (PR-A1) ────

@test "dispatch pointer removed: last-Eidolon remove cleans CLAUDE/GEMINI/copilot blocks; user content preserved" {
  # Seed a single-member manifest so atlas IS the last Eidolon.
  seed_manifest

  # Seed user-authored content surrounding the dispatch-pointer block.
  cat > CLAUDE.md <<'USER_CLAUDE'
# Personal Claude notes

Some pre-existing user content above.

USER_CLAUDE

  # Apply the dispatch-pointer block (and a cortex block in CLAUDE.md for G-A1.2 round-trip).
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    upsert_marker_block CLAUDE.md cortex 'cortex body for removal test'
    apply_dispatch_pointers 'CLAUDE.md,GEMINI.md,.github/copilot-instructions.md'
  " 2>/dev/null

  # Confirm both blocks landed in CLAUDE.md before the remove.
  grep -qF "<!-- eidolon:dispatch-pointer start -->" CLAUDE.md
  grep -qF "<!-- eidolon:cortex start -->"           CLAUDE.md
  [ -f GEMINI.md ]
  [ -f .github/copilot-instructions.md ]

  # Run eidolons remove atlas (the only member → last-Eidolon path).
  # The stub dies after the cleanup, so we accept non-zero exit but
  # assert on the resulting file state.
  run eidolons remove atlas
  [ "$status" -ne 0 ]

  # Both blocks gone from CLAUDE.md.
  ! grep -qF "<!-- eidolon:dispatch-pointer start -->" CLAUDE.md
  ! grep -qF "<!-- eidolon:cortex start -->"           CLAUDE.md

  # User content above the block survives byte-for-byte.
  grep -qF "# Personal Claude notes"              CLAUDE.md
  grep -qF "Some pre-existing user content above" CLAUDE.md

  # GEMINI.md and copilot file have their blocks stripped too. (When the
  # file held nothing but the block, what remains is an empty/whitespace
  # file — assert via absence-of-marker, not non-existence-of-file.)
  ! grep -qF "<!-- eidolon:dispatch-pointer start -->" GEMINI.md
  ! grep -qF "<!-- eidolon:dispatch-pointer start -->" .github/copilot-instructions.md
}
