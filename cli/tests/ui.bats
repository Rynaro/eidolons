#!/usr/bin/env bats
#
# UI-layer tests — exercises cli/src/ui/* primitives directly.
#
# Why a separate file: most bats tests run via the `eidolons` dispatcher
# in non-TTY mode, which forces EIDOLONS_FANCY=0 and exercises the plain
# branch only. These tests force fancy mode (FORCE_COLOR=1) so the box
# drawing and card rendering get exercised.

load helpers

@test "ui: theme detects fancy when FORCE_COLOR=1" {
  run env FORCE_COLOR=1 bash -c '. "$EIDOLONS_ROOT/cli/src/ui/theme.sh" && echo "$EIDOLONS_FANCY"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^1 ]]
}

@test "ui: theme detects plain when NO_COLOR=1" {
  run env NO_COLOR=1 bash -c '. "$EIDOLONS_ROOT/cli/src/ui/theme.sh" && echo "$EIDOLONS_FANCY"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^0 ]]
}

@test "ui: theme detects plain when EIDOLONS_PLAIN=1 (overrides FORCE_COLOR)" {
  run env FORCE_COLOR=1 EIDOLONS_PLAIN=1 bash -c '. "$EIDOLONS_ROOT/cli/src/ui/theme.sh" && echo "$EIDOLONS_FANCY"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^0 ]]
}

@test "ui: theme detects plain in CI" {
  run env CI=true bash -c 'unset NO_COLOR FORCE_COLOR; . "$EIDOLONS_ROOT/cli/src/ui/theme.sh" && echo "$EIDOLONS_FANCY"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^0 ]]
}

@test "ui: ui_banner emits the wordmark in fancy mode" {
  run env FORCE_COLOR=1 NEXUS="$EIDOLONS_ROOT" bash -c '. "$EIDOLONS_ROOT/cli/src/ui/theme.sh" && . "$EIDOLONS_ROOT/cli/src/ui/panel.sh" && ui_banner 9.9.9 2>&1'
  [ "$status" -eq 0 ]
  # Block-art chars from art/banner.txt should be present.
  [[ "$output" == *"█"* ]]
  [[ "$output" =~ v9\.9\.9 ]]
}

@test "ui: ui_banner is silent in plain mode" {
  run env NO_COLOR=1 NEXUS="$EIDOLONS_ROOT" bash -c '. "$EIDOLONS_ROOT/cli/src/ui/theme.sh" && . "$EIDOLONS_ROOT/cli/src/ui/panel.sh" && ui_banner 9.9.9 2>&1'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ui: ui_section renders a Unicode rule in fancy mode" {
  run env FORCE_COLOR=1 bash -c '. "$EIDOLONS_ROOT/cli/src/ui/theme.sh" && . "$EIDOLONS_ROOT/cli/src/ui/panel.sh" && ui_section "Hello" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" =~ Hello ]]
  [[ "$output" == *"─"* ]]
}

@test "ui: ui_section uses ASCII fallback in plain mode" {
  run env NO_COLOR=1 bash -c '. "$EIDOLONS_ROOT/cli/src/ui/theme.sh" && . "$EIDOLONS_ROOT/cli/src/ui/panel.sh" && ui_section "Hello" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "=== Hello ===" ]]
}

@test "ui: ui_card renders a JRPG card frame in fancy mode" {
  run env FORCE_COLOR=1 EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c '
    . "$EIDOLONS_ROOT/cli/src/lib.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/card.sh"
    ui_card atlas
  '
  [ "$status" -eq 0 ]
  # Outer double-line card frame.
  [[ "$output" == *"╔"* ]]
  [[ "$output" == *"╠"* ]]
  [[ "$output" == *"╚"* ]]
  # The sigil at art/eidolons/atlas.txt contains a stylized "▲".
  [[ "$output" == *"▲"* ]]
  # Card title still surfaces the eidolon's display name.
  [[ "$output" =~ ATLAS ]]
}

@test "ui: ui_card falls back to text dump in plain mode" {
  run env NO_COLOR=1 EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c '
    . "$EIDOLONS_ROOT/cli/src/lib.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/card.sh"
    ui_card atlas
  '
  [ "$status" -eq 0 ]
  # No box drawing — just the legacy key/value layout.
  [[ "$output" != *"╔"* ]]
  [[ "$output" =~ ATLAS ]]
  [[ "$output" =~ Methodology: ]]
  [[ "$output" =~ Handoffs: ]]
  [[ "$output" =~ Security: ]]
}

@test "ui: every roster eidolon has a sigil file" {
  for n in atlas spectra apivr idg forge vigil; do
    [ -f "$EIDOLONS_ROOT/art/eidolons/$n.txt" ] || {
      echo "missing sigil: $n" >&2
      false
    }
  done
}

@test "ui: ui_load_sigil emits exactly UI_SIGIL_HEIGHT (6) rows" {
  # Width is byte-vs-char-sensitive across awk/bash/perl, so we don't
  # assert raw column counts here. The card-render test above
  # ("ui: ui_card renders a JRPG card frame ...") covers visible
  # alignment by virtue of the card rendering at all.
  run env EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c '
    . "$EIDOLONS_ROOT/cli/src/ui/theme.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/glyphs.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/art_loader.sh"
    ui_load_sigil atlas | wc -l
  '
  [ "$status" -eq 0 ]
  # `wc -l` strips leading whitespace differently per platform — trim it.
  trimmed="$(echo "$output" | tr -d ' ')"
  [ "$trimmed" = "6" ]
}
