#!/usr/bin/env bash
# cli/src/ui/art_loader.sh — locate and read static ASCII art assets.
#
# Sigils live at $NEXUS/art/eidolons/<name>.txt — 12 cols × 6 rows of
# hand-authored ASCII per Eidolon (frameless — the card supplies its
# own outer frame). The loader normalises each line to a fixed column
# width so cards render cleanly regardless of the sigil's raw character
# counts.
#
# Public API:
#   ui_load_sigil <name>       echoes sigil text (one row per line)
#   ui_sigil_exists <name>     0 if the sigil file is present
#   ui_sigil_width             column width sigils are padded to (constant)
#   ui_sigil_height            row count sigils are padded to (constant)
# ═══════════════════════════════════════════════════════════════════════════

[[ "${EIDOLONS_UI_ART_LOADER_LOADED:-0}" == "1" ]] && return 0
EIDOLONS_UI_ART_LOADER_LOADED=1

# Fixed dimensions — keeps card.sh's two-column layout deterministic.
# Reduced from 14×8 to 12×6 when sigils dropped their inner frame and
# role-label row (see specs/ascii-art-redesign.md). Any change here
# requires simultaneous edits to every art/eidolons/*.txt file and a
# re-run of cli/tests/art-lint.sh.
UI_SIGIL_WIDTH=12
UI_SIGIL_HEIGHT=6

ui_sigil_width()  { echo "$UI_SIGIL_WIDTH"; }
ui_sigil_height() { echo "$UI_SIGIL_HEIGHT"; }

_ui_sigil_path() {
  local name="$1"
  local nexus="${NEXUS:-${EIDOLONS_NEXUS:-}}"
  [[ -z "$nexus" ]] && return 1
  local path="$nexus/art/eidolons/${name}.txt"
  [[ -f "$path" ]] || return 1
  echo "$path"
}

ui_sigil_exists() {
  _ui_sigil_path "$1" >/dev/null 2>&1
}

# Pad a string to N display columns. We use ${#s} which counts bytes in
# bash 3.2; the sigils only use Unicode chars whose terminal display
# width matches our intended column count (1 cell each), so byte-based
# padding works correctly for them. If a sigil is hand-authored with a
# wide-display char (CJK, emoji), this would mis-align — keep authoring
# constrained to the box-drawing / block / dingbat ranges.
_ui_pad_line() {
  local line="$1" width="$2"
  # Strip trailing newline if any (read -r generally already does).
  local pad=$((width - ${#line}))
  if [[ "$pad" -gt 0 ]]; then
    local spaces=""
    while [[ "$pad" -gt 0 ]]; do
      spaces="${spaces} "
      pad=$((pad - 1))
    done
    printf '%s%s' "$line" "$spaces"
  else
    printf '%s' "$line"
  fi
}

# Echo a sigil. Each row is padded to UI_SIGIL_WIDTH columns; output
# always has exactly UI_SIGIL_HEIGHT rows (truncated or blank-padded
# at the bottom). The caller can rely on a stable rectangle.
ui_load_sigil() {
  local name="$1"
  local path; path="$(_ui_sigil_path "$name")" || return 1

  local count=0
  while IFS= read -r line; do
    if [[ "$count" -ge "$UI_SIGIL_HEIGHT" ]]; then
      break
    fi
    _ui_pad_line "$line" "$UI_SIGIL_WIDTH"
    printf '\n'
    count=$((count + 1))
  done < "$path"

  # Bottom-pad with blank rows if the file is shorter than expected.
  while [[ "$count" -lt "$UI_SIGIL_HEIGHT" ]]; do
    _ui_pad_line "" "$UI_SIGIL_WIDTH"
    printf '\n'
    count=$((count + 1))
  done
}
