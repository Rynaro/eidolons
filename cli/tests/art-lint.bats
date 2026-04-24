#!/usr/bin/env bats
#
# Art-lint tests — wraps cli/tests/art-lint.sh so the mechanical gates
# (G1..G8) run as part of the regular `bats cli/tests/` sweep, and adds
# G9 (loader contract) integration.

load helpers

@test "art-lint: script is executable and passes for shipped assets" {
  run bash "$EIDOLONS_ROOT/cli/tests/art-lint.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "art-lint: OK" ]]
}

@test "art-lint: G1 — every sigil row is exactly UI_SIGIL_WIDTH display cols" {
  # Uses python3 to count Unicode scalar width (not bytes). If python3
  # isn't on PATH in CI, this should surface as a setup failure long
  # before reaching here — yaml_to_json already depends on it.
  run env EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c '
    . "$EIDOLONS_ROOT/cli/src/ui/art_loader.sh"
    want="$UI_SIGIL_WIDTH"
    fail=0
    for f in "$EIDOLONS_ROOT"/art/eidolons/*.txt; do
      python3 - "$f" "$want" <<PY
import sys, unicodedata
path, want = sys.argv[1], int(sys.argv[2])
with open(path, "r", encoding="utf-8") as fh:
    for i, raw in enumerate(fh, 1):
        line = raw.rstrip("\n")
        w = sum(2 if unicodedata.east_asian_width(c) in ("W","F") else 1 for c in line)
        if w != want:
            print(f"{path}:{i}: width {w} != {want}", file=sys.stderr)
            sys.exit(1)
PY
      [[ "$?" -ne 0 ]] && fail=1
    done
    exit "$fail"
  '
  [ "$status" -eq 0 ]
}

@test "art-lint: G9 — ui_load_sigil emits UI_SIGIL_HEIGHT rows × UI_SIGIL_WIDTH display cols" {
  # Integration test: the loader rectangle matches the declared constants
  # for every shipped sigil.
  for name in atlas spectra apivr forge idg vigil; do
    run env EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c "
      . '$EIDOLONS_ROOT/cli/src/ui/theme.sh'
      . '$EIDOLONS_ROOT/cli/src/ui/glyphs.sh'
      . '$EIDOLONS_ROOT/cli/src/ui/art_loader.sh'
      ui_load_sigil '$name' | awk 'END{print NR}'
    "
    [ "$status" -eq 0 ]
    row_count="$(echo "$output" | tr -d ' ')"
    [ "$row_count" = "6" ] || { echo "$name row_count=$row_count" >&2; false; }

    # Width check via a python one-liner per sigil. Load the sigil,
    # ensure every line is exactly 12 display cols.
    run env EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c "
      . '$EIDOLONS_ROOT/cli/src/ui/theme.sh'
      . '$EIDOLONS_ROOT/cli/src/ui/glyphs.sh'
      . '$EIDOLONS_ROOT/cli/src/ui/art_loader.sh'
      ui_load_sigil '$name' | python3 -c 'import sys, unicodedata
for raw in sys.stdin:
    line = raw.rstrip(chr(10))
    w = sum(2 if unicodedata.east_asian_width(c) in (\"W\",\"F\") else 1 for c in line)
    if w != 12:
        print(\"width\", w, \"!= 12\", repr(line))
        sys.exit(1)
'
    "
    [ "$status" -eq 0 ] || { echo "$name width fail: $output" >&2; false; }
  done
}

@test "art-lint: sigil files contain no double-line box-drawing chars" {
  # Redundancy with G6 in the lint script — kept here because a silent
  # regression to ═║╔╗╚╝ inside a sigil would be the most likely
  # visual-clash failure mode once someone hand-edits without running
  # the lint.
  for f in "$EIDOLONS_ROOT"/art/eidolons/*.txt; do
    run grep -l -E '═|║|╔|╗|╚|╝|╠|╣|╦|╩|╬' "$f"
    [ "$status" -ne 0 ] || {
      echo "double-line box-drawing found in $f" >&2
      false
    }
  done
}

@test "art-lint: sigil files have no role-word row (sentinel/planner/coder/...)" {
  # Spec §OQ-3: role words are rendered from capability_class in the
  # card title, not baked into the art file. A regression would have the
  # word appear somewhere in the file body.
  for f in "$EIDOLONS_ROOT"/art/eidolons/*.txt; do
    run grep -iE 'sentinel|planner|coder|scriber|reasoner|debugger' "$f"
    [ "$status" -ne 0 ] || {
      echo "role-word found in $f" >&2
      false
    }
  done
}
