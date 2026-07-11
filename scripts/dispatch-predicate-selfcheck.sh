#!/usr/bin/env bash
# scripts/dispatch-predicate-selfcheck.sh — derivability self-check for the
# Step-2(a)/(b) fixture table (AC-C11; also exercises AC-C05/AC-C06).
#
# Re-derives S1..S5 for all seventeen frozen fixtures by running
# scripts/dispatch-predicate-extractor.sh on each fixture prompt, diffs the
# result against the frozen columns in the fixtures TSV, and separately
# re-derives the Route column from (declared S6/S7) + (computed S1..S5) via
# the frozen combinator:
#   S7==0            -> chain
#   S6==1 && S7==1   -> generalist iff S1&&S2&&S3&&S4&&S5, else clarification_request
#
# Exits 0 iff all seventeen rows match on every column (S1..S5 AND route),
# zero hand-edited cells (CRIT-013/R-049/R-054).
#
# Usage:
#   dispatch-predicate-selfcheck.sh [fixtures.tsv]
#
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXUS_ROOT="$(cd "$SELF_DIR/.." && pwd)"
EXTRACTOR="$SELF_DIR/dispatch-predicate-extractor.sh"
FIXTURES="${1:-$NEXUS_ROOT/cli/tests/fixtures/dispatch-predicate/fixtures.tsv}"

if [ ! -f "$FIXTURES" ]; then
  printf '[ERROR] fixtures file not found: %s\n' "$FIXTURES" >&2
  exit 2
fi
if [ ! -x "$EXTRACTOR" ]; then
  printf '[ERROR] extractor not found or not executable: %s\n' "$EXTRACTOR" >&2
  exit 2
fi

total=0
mismatches=0
first_line=1

while IFS="$(printf '\t')" read -r id prompt f_s1 f_s2 f_s3 f_s4 f_s5 f_s6 f_s7 f_route; do
  if [ "$first_line" -eq 1 ]; then
    first_line=0
    continue # header row
  fi
  [ -z "$id" ] && continue

  total=$((total + 1))

  computed="$("$EXTRACTOR" "$prompt")"
  c_s1="$(printf '%s' "$computed" | awk '{print $1}')"
  c_s2="$(printf '%s' "$computed" | awk '{print $2}')"
  c_s3="$(printf '%s' "$computed" | awk '{print $3}')"
  c_s4="$(printf '%s' "$computed" | awk '{print $4}')"
  c_s5="$(printf '%s' "$computed" | awk '{print $5}')"

  row_ok=1
  if [ "$c_s1" != "$f_s1" ] || [ "$c_s2" != "$f_s2" ] || [ "$c_s3" != "$f_s3" ] || \
     [ "$c_s4" != "$f_s4" ] || [ "$c_s5" != "$f_s5" ]; then
    row_ok=0
    printf '[MISMATCH] %s: frozen S1..S5=(%s %s %s %s %s) computed=(%s %s %s %s %s)\n' \
      "$id" "$f_s1" "$f_s2" "$f_s3" "$f_s4" "$f_s5" "$c_s1" "$c_s2" "$c_s3" "$c_s4" "$c_s5" >&2
  fi

  # Re-derive route from declared S6/S7 + computed S1..S5.
  if [ "$f_s7" = "0" ]; then
    d_route="chain"
  elif [ "$f_s6" = "1" ] && [ "$f_s7" = "1" ]; then
    if [ "$c_s1" = "1" ] && [ "$c_s2" = "1" ] && [ "$c_s3" = "1" ] && [ "$c_s4" = "1" ] && [ "$c_s5" = "1" ]; then
      d_route="generalist"
    else
      d_route="clarification_request"
    fi
  else
    d_route="dispatch" # S6=0 case — not exercised by these 17 fixtures
  fi

  if [ "$d_route" != "$f_route" ]; then
    row_ok=0
    printf '[MISMATCH] %s: frozen route=%s derived route=%s\n' "$id" "$f_route" "$d_route" >&2
  fi

  if [ "$row_ok" -eq 0 ]; then
    mismatches=$((mismatches + 1))
  fi
done < "$FIXTURES"

printf '[dispatch-predicate-selfcheck] %s fixtures checked, %s mismatch(es)\n' "$total" "$mismatches" >&2

if [ "$mismatches" -gt 0 ]; then
  printf '[FAIL] derivability self-check found %s mismatch(es)\n' "$mismatches" >&2
  exit 1
fi

printf '[PASS] all %s fixtures match the frozen table exactly (zero hand-edited cells)\n' "$total" >&2
exit 0
