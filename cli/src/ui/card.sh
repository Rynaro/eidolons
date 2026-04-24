#!/usr/bin/env bash
# cli/src/ui/card.sh — JRPG-style character card for an Eidolon.
#
# Layout (fancy mode):
#
#   ╔══════════════════════════════════════════════════════════════╗
#   ║  ATLAS  ·  scout  ·  v1.0.3  ·  shipped                      ║
#   ╠════════════════╦═════════════════════════════════════════════╣
#   ║   <sigil>      ║  Methodology  ATLAS v1.0                    ║
#   ║   14×8 cell    ║  Cycle        A→T→L→A→S                     ║
#   ║                ║  Tokens       900 / 3500                    ║
#   ║                ║                                             ║
#   ║                ║  Handoffs                                   ║
#   ║                ║    ↑  —                                     ║
#   ║                ║    ↓  spectra, apivr                        ║
#   ║                ║                                             ║
#   ╚════════════════╩═════════════════════════════════════════════╝
#
# Plain mode: falls back to the existing key/value text dump used by
# `eidolons roster <name>` so test assertions on substrings (display
# name, methodology, cycle, etc.) keep matching.
#
# Public API:
#   ui_card <eidolon-name>        prints the card to stdout
#
# Reads roster data through roster_get (lib.sh) — never re-parses YAML.
# ═══════════════════════════════════════════════════════════════════════════

[[ "${EIDOLONS_UI_CARD_LOADED:-0}" == "1" ]] && return 0
EIDOLONS_UI_CARD_LOADED=1

_ui_card_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_ui_card_dir/theme.sh"
# shellcheck disable=SC1091
. "$_ui_card_dir/glyphs.sh"
# shellcheck disable=SC1091
. "$_ui_card_dir/art_loader.sh"
unset _ui_card_dir

# Total card width (outer frame to outer frame). Sigil column is fixed
# at UI_SIGIL_WIDTH+4 (4 = inner padding + dividers); stats column gets
# the rest.
UI_CARD_WIDTH=66

_ui_repeat_card() {
  local char="$1" count="$2" out=""
  while [[ "$count" -gt 0 ]]; do
    out="${out}${char}"
    count=$((count - 1))
  done
  printf '%s' "$out"
}

# Strip ANSI escape sequences (simple regex — only handles CSI sequences
# we generate, which is enough for our padding math).
_ui_strip_ansi() {
  # shellcheck disable=SC2001
  echo "$1" | sed $'s/\033\\[[0-9;]*m//g'
}

# Return the display column width of a string (after ANSI strip). ASCII
# printable + BMP narrow chars = 1 col each; East-Asian Wide/Fullwidth = 2;
# combining marks (U+0300..U+036F), variation selectors (U+FE00..U+FE0F),
# zero-width joiner/non-joiner (U+200C/U+200D) = 0. Uses python3 because
# bash 3.2's ${#var} counts BYTES, not display columns — UTF-8 arrows
# (↑↓→) are 3 bytes each but 1 column, which breaks padding math.
# Output goes to stdout only; no log chatter (keeps command-substitution safe).
_ui_display_width() {
  # Fast-path for pure ASCII strings — avoids spawning python3 per row.
  case "$1" in
    *[!\ -~]*) : ;;
    *) printf '%d' "${#1}"; return 0 ;;
  esac
  python3 - "$1" <<'PY'
import sys, re, unicodedata
s = sys.argv[1]
s = re.sub(r'\x1b\[[0-9;]*m', '', s)
w = 0
for c in s:
    cp = ord(c)
    if 0x0300 <= cp <= 0x036F:      w += 0   # combining marks
    elif 0xFE00 <= cp <= 0xFE0F:    w += 0   # variation selectors
    elif cp in (0x200C, 0x200D):    w += 0   # ZWJ / ZWNJ
    elif unicodedata.east_asian_width(c) in ("W", "F"): w += 2
    else:                           w += 1
sys.stdout.write(str(w))
PY
}

# Truncate a string to at most <max_cols> display columns, adding a
# trailing ellipsis (U+2026, 1 col) when truncation occurs. Preserves
# any ANSI SGR sequences present in the input and always appends RESET
# if the input carried any escape so we never emit a dangling color.
# Edge cases:
#   - If the string already fits, returns it unchanged.
#   - If max_cols < 2, truncates without ellipsis.
# Output is via stdout only.
_ui_truncate() {
  local str="$1" max_cols="$2"
  # Fast-path: ASCII-only AND short enough → no work.
  case "$str" in
    *[!\ -~]*) : ;;
    *)
      if [[ "${#str}" -le "$max_cols" ]]; then
        printf '%s' "$str"
        return 0
      fi
      ;;
  esac
  python3 - "$str" "$max_cols" <<'PY'
import sys, re, unicodedata
raw = sys.argv[1]
max_cols = int(sys.argv[2])
ansi_re = re.compile(r'\x1b\[[0-9;]*m')

def cwidth(c):
    cp = ord(c)
    if 0x0300 <= cp <= 0x036F:       return 0
    if 0xFE00 <= cp <= 0xFE0F:       return 0
    if cp in (0x200C, 0x200D):       return 0
    if unicodedata.east_asian_width(c) in ("W", "F"): return 2
    return 1

# Compute total display width (ANSI-stripped).
total = sum(cwidth(c) for c in ansi_re.sub('', raw))
if total <= max_cols:
    sys.stdout.write(raw)
    sys.exit(0)

had_ansi = bool(ansi_re.search(raw))
ellipsis = '…'
use_ellipsis = max_cols >= 2
budget = max_cols - (1 if use_ellipsis else 0)

out = []
col = 0
i = 0
while i < len(raw):
    # Pass ANSI escape sequences through without counting them.
    m = ansi_re.match(raw, i)
    if m:
        out.append(m.group(0))
        i = m.end()
        continue
    c = raw[i]
    w = cwidth(c)
    if col + w > budget:
        break
    out.append(c)
    col += w
    i += 1

if use_ellipsis:
    out.append(ellipsis)
if had_ansi:
    out.append('\x1b[0m')
sys.stdout.write(''.join(out))
PY
}

# Print a content row with left + center + right vertical bars. Pads
# text columns so the right border lines up. Args: <sigil_line>
# <stat_line>.
_ui_card_row() {
  local sigil_line="$1" stat_line="$2"
  local sigil_w="$UI_SIGIL_WIDTH"
  # Layout (chars): L(1) + sp(1) + sigil(UI_SIGIL_WIDTH) + sp(1) + M(1)
  #                 + sp(1) + stats(?) + sp(1) + R(1)
  # → stats_w = UI_CARD_WIDTH - UI_SIGIL_WIDTH - 7
  local stats_w=$((UI_CARD_WIDTH - sigil_w - 7))
  # Truncate overflow and measure via display columns (not bytes) so
  # UTF-8 arrows and the like pad correctly.
  stat_line="$(_ui_truncate "$stat_line" "$stats_w")"
  local stat_w; stat_w="$(_ui_display_width "$(_ui_strip_ansi "$stat_line")")"
  local stat_pad=$((stats_w - stat_w))
  [[ "$stat_pad" -lt 0 ]] && stat_pad=0
  local pad_str; pad_str="$(_ui_repeat_card " " "$stat_pad")"

  printf '%s%s%s' "${UI_PRIMARY}" "$GLYPH_D_V" "${RESET}"      # left frame
  printf ' '
  printf '%s%s%s' "${UI_ACCENT}" "$sigil_line" "${RESET}"       # sigil cell
  printf ' '
  printf '%s%s%s' "${UI_PRIMARY}" "$GLYPH_D_V" "${RESET}"      # inner divider
  printf ' '
  printf '%s%s' "$stat_line" "$pad_str"                          # stats cell
  printf ' '
  printf '%s%s%s\n' "${UI_PRIMARY}" "$GLYPH_D_V" "${RESET}"    # right frame
}

# Print a header row spanning the full card width (used for the title bar).
_ui_card_header_row() {
  local title="$1"
  local inner_w=$((UI_CARD_WIDTH - 4))
  title="$(_ui_truncate "$title" "$inner_w")"
  local title_w; title_w="$(_ui_display_width "$(_ui_strip_ansi "$title")")"
  local pad=$((inner_w - title_w))
  [[ "$pad" -lt 0 ]] && pad=0
  local pad_str; pad_str="$(_ui_repeat_card " " "$pad")"

  printf '%s%s%s' "${UI_PRIMARY}" "$GLYPH_D_V" "${RESET}"
  printf ' '
  printf '%s%s' "$title" "$pad_str"
  printf ' '
  printf '%s%s%s\n' "${UI_PRIMARY}" "$GLYPH_D_V" "${RESET}"
}

# Build a horizontal frame line. Args: <left> <fill> <middle> <right>
# where middle goes after sigil_w+2 fill chars, splitting the row.
_ui_card_frame() {
  local left="$1" fill="$2" middle="$3" right="$4"
  local sigil_seg=$((UI_SIGIL_WIDTH + 2))
  local stats_seg=$((UI_CARD_WIDTH - sigil_seg - 3))
  local fill_left fill_right
  fill_left="$(_ui_repeat_card "$fill" "$sigil_seg")"
  fill_right="$(_ui_repeat_card "$fill" "$stats_seg")"
  printf '%s%s%s%s%s%s\n' \
    "${UI_PRIMARY}" "$left" "$fill_left" "$middle" "$fill_right" "${right}${RESET}"
}

# Build a top/bottom frame line that spans the full card (no center split).
_ui_card_frame_solid() {
  local left="$1" fill="$2" right="$3"
  local inner=$((UI_CARD_WIDTH - 2))
  local fill_str; fill_str="$(_ui_repeat_card "$fill" "$inner")"
  printf '%s%s%s%s%s\n' "${UI_PRIMARY}" "$left" "$fill_str" "$right" "${RESET}"
}

# ─── Plain-mode card (text dump) ──────────────────────────────────────────
# Reuses the legacy summary format that roster.sh used to print directly
# — preserves every test-pinned substring (display name, "Methodology:",
# "Cycle:", "Handoffs:", "upstream/downstream/lateral", "Token budget",
# "Security:", reads_repo etc.).
_ui_card_plain() {
  local entry="$1"
  local disp role meth cycle summary repo latest status
  local up down lat tok_entry tok_target sec_read sec_write sec_net

  disp="$(echo   "$entry" | jq -r '.display_name')"
  role="$(echo   "$entry" | jq -r '.capability_class')"
  meth="$(echo   "$entry" | jq -r '.methodology.name + " v" + .methodology.version')"
  cycle="$(echo  "$entry" | jq -r '.methodology.cycle')"
  summary="$(echo "$entry" | jq -r '.methodology.summary')"
  repo="$(echo   "$entry" | jq -r '.source.repo')"
  latest="$(echo "$entry" | jq -r '.versions.latest')"
  status="$(echo "$entry" | jq -r '.status')"
  up="$(echo     "$entry" | jq -r '.handoffs.upstream   | if length == 0 then "—" else join(", ") end')"
  down="$(echo   "$entry" | jq -r '.handoffs.downstream | if length == 0 then "—" else join(", ") end')"
  lat="$(echo    "$entry" | jq -r '(.handoffs.lateral // []) | if length == 0 then "—" else join(", ") end')"
  tok_entry="$(echo  "$entry" | jq -r '.working_set_tokens.entry  // "n/a"')"
  tok_target="$(echo "$entry" | jq -r '.working_set_tokens.target // "n/a"')"
  sec_read="$(echo   "$entry" | jq -r '.security.reads_repo')"
  sec_write="$(echo  "$entry" | jq -r '.security.writes_repo')"
  sec_net="$(echo    "$entry" | jq -r '.security.reads_network')"

  printf "%s%s%s — %s\n\n" "$BOLD" "$disp" "$RESET" "$role"
  printf "Methodology:  %s\n" "$meth"
  printf "Cycle:        %s\n" "$cycle"
  printf "Summary:      %s\n" "$summary"
  printf "Repo:         github.com/%s\n" "$repo"
  printf "Latest:       %s\n" "$latest"
  printf "Status:       %s\n\n" "$status"

  printf "Handoffs:\n"
  printf "  upstream:    %s\n" "$up"
  printf "  downstream:  %s\n" "$down"
  printf "  lateral:     %s\n\n" "$lat"

  printf "Token budget:\n"
  printf "  entry:            %s tokens\n" "$tok_entry"
  printf "  working set:      %s tokens\n\n" "$tok_target"

  printf "Security:\n"
  printf "  reads repo:    %s\n" "$sec_read"
  printf "  writes repo:   %s\n" "$sec_write"
  printf "  reads network: %s\n" "$sec_net"
}

# ─── Public entry point ───────────────────────────────────────────────────
ui_card() {
  local name="$1"
  local entry; entry="$(roster_get "$name")"

  if [[ "${EIDOLONS_FANCY:-0}" != "1" ]]; then
    _ui_card_plain "$entry"
    return 0
  fi

  local disp role latest status
  local meth cycle up down lat tok_entry tok_target
  disp="$(echo   "$entry" | jq -r '.display_name')"
  role="$(echo   "$entry" | jq -r '.capability_class')"
  latest="$(echo "$entry" | jq -r '.versions.latest')"
  status="$(echo "$entry" | jq -r '.status')"
  meth="$(echo   "$entry" | jq -r '.methodology.name + " v" + .methodology.version')"
  cycle="$(echo  "$entry" | jq -r '.methodology.cycle')"
  up="$(echo     "$entry" | jq -r '.handoffs.upstream   | if length == 0 then "—" else join(", ") end')"
  down="$(echo   "$entry" | jq -r '.handoffs.downstream | if length == 0 then "—" else join(", ") end')"
  lat="$(echo    "$entry" | jq -r '(.handoffs.lateral // []) | if length == 0 then "—" else join(", ") end')"
  tok_entry="$(echo  "$entry" | jq -r '.working_set_tokens.entry  // "n/a"')"
  tok_target="$(echo "$entry" | jq -r '.working_set_tokens.target // "n/a"')"

  # Build the title line with role/version/status badges separated by middots.
  local title
  title="$(printf '%s%s%s  %s·%s  %s  %s·%s  v%s  %s·%s  %s' \
    "${BOLD}${UI_ACCENT}" "$disp" "${RESET}" \
    "${UI_MUTED}" "${RESET}" \
    "$role" \
    "${UI_MUTED}" "${RESET}" \
    "$latest" \
    "${UI_MUTED}" "${RESET}" \
    "$status")"

  # Stats column rows. Pad in render via _ui_card_row.
  local s_methodology s_cycle s_tokens s_blank s_handoffs s_up s_down s_lateral
  s_methodology="$(printf '%sMethodology%s  %s' "${UI_MUTED}" "${RESET}" "$meth")"
  s_cycle="$(printf       '%sCycle%s        %s' "${UI_MUTED}" "${RESET}" "$cycle")"
  s_tokens="$(printf      '%sTokens%s       %s / %s' "${UI_MUTED}" "${RESET}" "$tok_entry" "$tok_target")"
  s_blank=""
  s_handoffs="$(printf    '%sHandoffs%s' "${UI_MUTED}" "${RESET}")"
  s_up="$(printf          '  %s%s%s  upstream    %s' "${UI_INFO}" "$GLYPH_ARROW_UP"   "${RESET}" "$up")"
  s_down="$(printf        '  %s%s%s  downstream  %s' "${UI_INFO}" "$GLYPH_ARROW_DOWN" "${RESET}" "$down")"
  s_lateral="$(printf     '  %s%s%s  lateral     %s' "${UI_INFO}" "$GLYPH_ARROW_RIGHT" "${RESET}" "$lat")"

  # Load the sigil into 8 rows.
  local sigil_rows=() sigil_line
  if ui_sigil_exists "$name"; then
    while IFS= read -r sigil_line; do
      sigil_rows+=("$sigil_line")
    done < <(ui_load_sigil "$name")
  else
    # No sigil → blank cells.
    local i=0
    while [[ "$i" -lt "$UI_SIGIL_HEIGHT" ]]; do
      sigil_rows+=("$(_ui_repeat_card " " "$UI_SIGIL_WIDTH")")
      i=$((i + 1))
    done
  fi

  local stat_rows=( "$s_methodology" "$s_cycle" "$s_tokens" "$s_blank" "$s_handoffs" "$s_up" "$s_down" "$s_lateral" )
  local stat_count=${#stat_rows[@]}

  # The card renders max(UI_SIGIL_HEIGHT, stat_count) body rows so the
  # stats never get clipped when the sigil envelope shrinks. Any sigil
  # row index beyond the sigil's height is filled with blank padding.
  local body_rows="$UI_SIGIL_HEIGHT"
  if [[ "$stat_count" -gt "$body_rows" ]]; then
    body_rows="$stat_count"
  fi

  # Pre-compute a blank sigil row so overflow rows keep the left cell
  # visually aligned with the outer frame.
  local blank_sigil; blank_sigil="$(_ui_repeat_card " " "$UI_SIGIL_WIDTH")"

  # ─── Render ─────────────────────────────────────────────────────────
  _ui_card_frame_solid "$GLYPH_D_TL" "$GLYPH_D_H" "$GLYPH_D_TR"
  _ui_card_header_row  "$title"
  _ui_card_frame       "$GLYPH_D_L" "$GLYPH_D_H" "$GLYPH_D_T" "$GLYPH_D_R"

  local i=0
  while [[ "$i" -lt "$body_rows" ]]; do
    local sig
    if [[ "$i" -lt "$UI_SIGIL_HEIGHT" ]]; then
      sig="${sigil_rows[$i]:-$blank_sigil}"
    else
      sig="$blank_sigil"
    fi
    local stat="${stat_rows[$i]:-}"
    # Pad sigil to fixed width if shorter (defensive — art_loader already does this).
    local sig_visible; sig_visible="$(_ui_strip_ansi "$sig")"
    if [[ "${#sig_visible}" -lt "$UI_SIGIL_WIDTH" ]]; then
      sig="$(_ui_pad_line "$sig" "$UI_SIGIL_WIDTH")"
    fi
    _ui_card_row "$sig" "$stat"
    i=$((i + 1))
  done

  _ui_card_frame "$GLYPH_D_BL" "$GLYPH_D_H" "$GLYPH_D_B" "$GLYPH_D_BR"
}
