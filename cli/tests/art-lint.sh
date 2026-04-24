#!/usr/bin/env bash
# cli/tests/art-lint.sh — structural validator for ASCII art assets.
#
# Enforces the mechanical gates (G1..G8) from
# specs/ascii-art-redesign.md for every file under art/. G9 (loader
# contract) is enforced in cli/tests/art-lint.bats, which runs this
# script plus an integration call through ui_load_sigil.
#
# Gates
#   G1 width_uniformity   every row in a file has the same display-column width
#   G2 no_trailing_tabs   no line ends with a tab (trailing spaces are permitted
#                         as envelope padding — see note below)
#   G3 no_tabs            no tab characters anywhere
#   G4 max_rows           sigils ≤ 6, banner ≤ 9
#   G5 max_cols           sigils ≤ 12, banner ≤ 60
#   G6 char_whitelist     every codepoint in palette (see spec §character-palette);
#                         double-line box-drawing banned in sigils
#   G7 file_terminator    ends with exactly one \n; no trailing empty line
#   G8 utf8_valid         iconv -f UTF-8 -t UTF-8 round-trips
#
# Note on trailing whitespace: frameless sigils often have blank cells
# at the right edge. G1 requires uniform row width, which means those
# rows MUST carry padding spaces to the envelope boundary. We therefore
# do not flag trailing spaces as a failure — G1 + G5 already constrain
# row shape, and G3 catches the actual footgun (tabs).
#
# Non-zero exit on any failure. Every failure prints
#     <file>:<line>: <rule-id> <message>
# so CI output is grep-able.
#
# Bash 3.2 compatible: no associative arrays, no readarray/mapfile, no
# &>> redirects. Relies on python3 for Unicode-aware width counting and
# codepoint inspection — python3 is already an implicit dev dependency
# (yaml_to_json fallback per CLAUDE.md), and Linux CI images ship it.
# ═══════════════════════════════════════════════════════════════════════════

set -u

ART_LINT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SIGIL_MAX_ROWS=6
SIGIL_MAX_COLS=12
BANNER_MAX_ROWS=9
BANNER_MAX_COLS=60

# Failure channel: we append one line per failure to this marker file.
# Using a file (not a variable) because bash pipelines run the RHS in
# subshells where variable assignments to FAIL would be lost.
ART_LINT_MARKER="$(mktemp -t eidolons-art-lint.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -f '$ART_LINT_MARKER'" EXIT

_fail() {
  # file, line, rule, message
  printf '%s:%s: %s %s\n' "$1" "$2" "$3" "$4" >&2
  printf 'F\n' >> "$ART_LINT_MARKER"
}

# ─── Palette check (pure bash, called per codepoint) ──────────────────────
# $1 = hex codepoint (e.g. "2501"), $2 = surface ("sigil" or "banner")
_cp_in_palette() {
  local hex="$1" surface="$2"
  local cp=$((16#$hex))

  # Hard bans regardless of surface.
  if [[ "$cp" -eq 160 ]]; then return 1; fi                         # NBSP
  if [[ "$cp" -ge 768  && "$cp" -le 879  ]]; then return 1; fi      # combining
  if [[ "$cp" -ge 65024 && "$cp" -le 65039 ]]; then return 1; fi    # variation selectors
  if [[ "$cp" -ge 127000 ]]; then return 1; fi                      # emoji+supplementary

  # Allowed ranges.
  if [[ "$cp" -ge 32    && "$cp" -le 126   ]]; then :               # ASCII printable
  elif [[ "$cp" -ge 8592  && "$cp" -le 8703  ]]; then :             # Arrows U+2190..U+21FF
  elif [[ "$cp" -ge 9472  && "$cp" -le 9599  ]]; then :             # Box U+2500..U+257F
  elif [[ "$cp" -ge 9600  && "$cp" -le 9631  ]]; then :             # Block U+2580..U+259F
  elif [[ "$cp" -ge 9632  && "$cp" -le 9727  ]]; then :             # Geometric U+25A0..U+25FF
  elif [[ "$cp" -ge 9728  && "$cp" -le 9983  ]]; then :             # Misc U+2600..U+26FF
  elif [[ "$cp" -ge 9984  && "$cp" -le 10175 ]]; then :             # Dingbats U+2700..U+27BF
  else
    return 1
  fi

  # Sigil extra ban: double-line box-drawing clashes with the card frame.
  # U+2550..U+256C covers ═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╦ ╩ ╬ and mixed single/double.
  if [[ "$surface" = "sigil" ]]; then
    if [[ "$cp" -ge 9552 && "$cp" -le 9580 ]]; then return 1; fi
  fi
  return 0
}

# ─── Main per-file lint ───────────────────────────────────────────────────
_lint_file() {
  local file="$1" surface="$2"
  local max_rows max_cols
  if [[ "$surface" = "sigil" ]]; then
    max_rows="$SIGIL_MAX_ROWS"; max_cols="$SIGIL_MAX_COLS"
  else
    max_rows="$BANNER_MAX_ROWS"; max_cols="$BANNER_MAX_COLS"
  fi

  # G8 — UTF-8 validity.
  if ! iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1; then
    _fail "$file" 0 G8 "file is not valid UTF-8"
    return
  fi

  # G7 — file terminator.
  local last_byte
  last_byte="$(tail -c 1 "$file" | od -An -tx1 | tr -d ' \n')"
  if [[ "$last_byte" != "0a" ]]; then
    _fail "$file" 0 G7 "file must end with a single \\n"
  fi
  local last_line
  last_line="$(awk 'END{print}' "$file")"
  if [[ -z "$last_line" ]]; then
    _fail "$file" 0 G7 "file has trailing empty line"
  fi

  # G3 — no tabs.
  if grep -nP '\t' "$file" >/dev/null 2>&1; then
    local tab_hits
    tab_hits="$(grep -nP '\t' "$file")"
    while IFS=: read -r lineno _rest; do
      [[ -z "$lineno" ]] && continue
      _fail "$file" "$lineno" G3 "tab character found"
    done <<EOF
$tab_hits
EOF
  fi

  # G2 — no trailing tabs specifically (spaces are allowed because
  # frameless art uses them for envelope padding; G1 keeps widths uniform).
  if grep -nP '\t$' "$file" >/dev/null 2>&1; then
    local ws_hits
    ws_hits="$(grep -nP '\t$' "$file")"
    while IFS=: read -r lineno _rest; do
      [[ -z "$lineno" ]] && continue
      _fail "$file" "$lineno" G2 "trailing tab"
    done <<EOF
$ws_hits
EOF
  fi

  # One python pass emits "<width>\t<hex,hex,...>" per line.
  local inspect_out
  inspect_out="$(python3 - "$file" <<'PY'
import sys, unicodedata
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    for raw in f:
        line = raw.rstrip("\n")
        w = 0
        cps = []
        for c in line:
            eaw = unicodedata.east_asian_width(c)
            w += 2 if eaw in ("W", "F") else 1
            cps.append("%04X" % ord(c))
        sys.stdout.write("%d\t%s\n" % (w, ",".join(cps)))
PY
)"

  # G4 — row count.
  local row_count=0
  if [[ -n "$inspect_out" ]]; then
    row_count="$(printf '%s\n' "$inspect_out" | wc -l | tr -d ' ')"
  fi
  if [[ "$row_count" -gt "$max_rows" ]]; then
    _fail "$file" "$row_count" G4 "file has $row_count rows; max for $surface is $max_rows"
  fi

  # G1, G5, G6 — per-row checks via heredoc (no subshell pipe).
  local first_width="" lineno=0
  while IFS=$'\t' read -r w cps; do
    lineno=$((lineno + 1))
    # Skip any ghost empty trailing record.
    if [[ -z "$w" && -z "$cps" ]]; then
      continue
    fi

    # G5 — max cols.
    if [[ "$w" -gt "$max_cols" ]]; then
      _fail "$file" "$lineno" G5 "row has $w display cols; max for $surface is $max_cols"
    fi

    # G1 — width uniformity.
    if [[ -z "$first_width" ]]; then
      first_width="$w"
    elif [[ "$w" != "$first_width" ]]; then
      _fail "$file" "$lineno" G1 "row width $w does not match first-row width $first_width"
    fi

    # G6 — palette.
    if [[ -n "$cps" ]]; then
      local IFS_SAVE="$IFS"
      IFS=','
      # shellcheck disable=SC2086
      set -- $cps
      IFS="$IFS_SAVE"
      local hex
      for hex in "$@"; do
        if ! _cp_in_palette "$hex" "$surface"; then
          _fail "$file" "$lineno" G6 "codepoint U+$hex not in palette (surface=$surface)"
        fi
      done
    fi
  done <<EOF
$inspect_out
EOF
}

# ─── Entry ────────────────────────────────────────────────────────────────
banner="$ART_LINT_ROOT/art/banner.txt"
if [[ -f "$banner" ]]; then
  _lint_file "$banner" banner
else
  _fail "$banner" 0 GX "missing banner file"
fi

for f in "$ART_LINT_ROOT"/art/eidolons/*.txt; do
  [[ -e "$f" ]] || continue
  _lint_file "$f" sigil
done

if [[ -s "$ART_LINT_MARKER" ]]; then
  printf '\nart-lint: FAIL\n' >&2
  exit 1
fi
printf 'art-lint: OK\n'
exit 0
