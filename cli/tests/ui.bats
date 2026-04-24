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
  # The sigil at art/eidolons/atlas.txt contains paired focal eyes "◉".
  [[ "$output" == *"◉"* ]]
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

# ─── Regression: card-row width math ──────────────────────────────────────
#
# These tests pin the fix for the overflow bug where a long stats row
# (e.g. VIGIL's lateral handoff list) pushed the right frame past the
# card boundary. Root cause was two-fold: (1) overflow was clamped in
# padding but the stat_line was still emitted in full; (2) ${#var}
# counts BYTES in bash 3.2, so UTF-8 arrows (↑↓→, 3 bytes / 1 col each)
# over-reported width and stole padding even when content fit.

@test "ui: _ui_display_width handles ASCII, UTF-8 arrows, and wide chars" {
  run env FORCE_COLOR=1 bash -c '
    . "$EIDOLONS_ROOT/cli/src/ui/theme.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/glyphs.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/art_loader.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/card.sh"
    printf "ascii=%s\n" "$(_ui_display_width "hello")"
    printf "arrow=%s\n" "$(_ui_display_width "→↑↓")"
    printf "mixed=%s\n" "$(_ui_display_width "x → y")"
    printf "ansi=%s\n"  "$(_ui_display_width "$(printf "\033[34m→\033[0m")")"
  '
  [ "$status" -eq 0 ]
  [[ "$output" =~ ascii=5 ]]
  [[ "$output" =~ arrow=3 ]]
  [[ "$output" =~ mixed=5 ]]
  [[ "$output" =~ ansi=1 ]]
}

@test "ui: _ui_truncate appends ellipsis on overflow, leaves short strings alone" {
  run env FORCE_COLOR=1 bash -c '
    . "$EIDOLONS_ROOT/cli/src/ui/theme.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/glyphs.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/art_loader.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/card.sh"
    printf "short=[%s]\n" "$(_ui_truncate "hi" 10)"
    printf "trunc=[%s]\n" "$(_ui_truncate "abcdefghij" 5)"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"short=[hi]"* ]]
  # 5 cols → 4 chars + ellipsis
  [[ "$output" == *"trunc=[abcd…]"* ]]
}

@test "ui: ui_card keeps every rendered card row at uniform display width" {
  # Regression: the VIGIL lateral row used to overflow to 69 display
  # columns while the rest rendered at 66. Bug was stats overflow not
  # being truncated + bytes-vs-display-cols miscount.
  run env FORCE_COLOR=1 EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c '
    . "$EIDOLONS_ROOT/cli/src/lib.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/card.sh"
    ui_card vigil
  '
  [ "$status" -eq 0 ]
  # All card-frame lines must have identical display width.
  widths="$(printf '%s\n' "$output" | python3 -c '
import sys, re, unicodedata
ansi = re.compile(r"\x1b\[[0-9;]*m")
seen = set()
for raw in sys.stdin:
    line = ansi.sub("", raw.rstrip("\n"))
    if not line or line[0] not in "║╔╠╚":
        continue
    w = 0
    for c in line:
        cp = ord(c)
        if 0x0300 <= cp <= 0x036F: continue
        if 0xFE00 <= cp <= 0xFE0F: continue
        if cp in (0x200C, 0x200D): continue
        w += 2 if unicodedata.east_asian_width(c) in ("W","F") else 1
    seen.add(w)
print(",".join(str(x) for x in sorted(seen)))
')"
  [ "$widths" = "66" ]
  # And the lateral row must be truncated with an ellipsis (it would
  # otherwise overflow by 3 cols on VIGIL's 5-member lateral list).
  [[ "$output" == *"lateral"* ]]
  [[ "$output" == *"…"* ]]
}

@test "ui: ui_card title bar truncates when the display name overflows" {
  # Inject a synthetic title string through _ui_card_header_row directly
  # — no need to mutate the roster for a pure layout test.
  run env FORCE_COLOR=1 bash -c '
    . "$EIDOLONS_ROOT/cli/src/ui/theme.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/glyphs.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/art_loader.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/card.sh"
    _ui_card_header_row "THIS_IS_A_VERY_LONG_TITLE_THAT_DEFINITELY_EXCEEDS_THE_INNER_CARD_WIDTH_BY_A_LOT"
  '
  [ "$status" -eq 0 ]
  # Strip ANSI and measure the single emitted line.
  clean="$(printf '%s' "$output" | sed $'s/\033\\[[0-9;]*m//g')"
  w="$(printf '%s' "$clean" | python3 -c '
import sys, unicodedata
line = sys.stdin.read().rstrip("\n")
w = 0
for c in line:
    cp = ord(c)
    if 0x0300 <= cp <= 0x036F: continue
    if 0xFE00 <= cp <= 0xFE0F: continue
    if cp in (0x200C, 0x200D): continue
    w += 2 if unicodedata.east_asian_width(c) in ("W","F") else 1
print(w)
')"
  [ "$w" = "66" ]
  # Ellipsis present — truncation happened.
  [[ "$output" == *"…"* ]]
}

@test "ui: ui_card pads rows with UTF-8 arrows without stealing display columns" {
  # ATLAS' row "  ↑  upstream    —" was susceptible to the byte/col
  # miscount: arrows are 3 bytes but 1 display col, so ${#var}
  # over-counted by 2 cols and stole 2 chars of padding. With the fix,
  # every row should be exactly 66 display cols.
  run env FORCE_COLOR=1 EIDOLONS_NEXUS="$EIDOLONS_ROOT" bash -c '
    . "$EIDOLONS_ROOT/cli/src/lib.sh"
    . "$EIDOLONS_ROOT/cli/src/ui/card.sh"
    ui_card atlas
  '
  [ "$status" -eq 0 ]
  widths="$(printf '%s\n' "$output" | python3 -c '
import sys, re, unicodedata
ansi = re.compile(r"\x1b\[[0-9;]*m")
seen = set()
for raw in sys.stdin:
    line = ansi.sub("", raw.rstrip("\n"))
    if not line or line[0] not in "║╔╠╚":
        continue
    w = 0
    for c in line:
        cp = ord(c)
        if 0x0300 <= cp <= 0x036F: continue
        if 0xFE00 <= cp <= 0xFE0F: continue
        if cp in (0x200C, 0x200D): continue
        w += 2 if unicodedata.east_asian_width(c) in ("W","F") else 1
    seen.add(w)
print(",".join(str(x) for x in sorted(seen)))
')"
  [ "$widths" = "66" ]
}
