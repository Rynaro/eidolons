#!/usr/bin/env bash
# scripts/token-budget-check.sh — cortex always-loaded token-budget CI gate
#
# ESL change generalist-eidolon, Track D (R-022/R-023/R-024; AC-D01/D02/D03).
#
# Counts a conservative `ceil(char_count / 4)` chars-per-token proxy over the
# bytes STRICTLY BETWEEN a start/end marker pair (default:
# `<!-- always-loaded:start -->` / `<!-- always-loaded:end -->`) and fails
# (exit 1) when the proxy count exceeds the ceiling (default 850 — a
# conservative margin under the I-C4 900-token invariant, to absorb
# chars/4-vs-real-BPE heuristic error).
#
# Deterministic: two runs on the same bytes give the same count by
# construction (no external tokenizer call, no network, no randomness).
#
# Usage:
#   token-budget-check.sh <file> [--ceiling N] [--start-marker S] [--end-marker E]
#
# Exit codes:
#   0 — proxy count <= ceiling
#   1 — proxy count >  ceiling (budget exceeded)
#   2 — usage error / file not found / markers not found in file
#
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

usage() {
  printf 'Usage: %s <file> [--ceiling N] [--start-marker S] [--end-marker E]\n' "$(basename "$0")" >&2
  printf 'Default ceiling: 850. Default markers: <!-- always-loaded:start/end -->\n' >&2
  exit 2
}

FILE=""
CEILING=850
START_MARKER="<!-- always-loaded:start -->"
END_MARKER="<!-- always-loaded:end -->"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ceiling)
      CEILING="${2:-}"
      shift 2
      ;;
    --start-marker)
      START_MARKER="${2:-}"
      shift 2
      ;;
    --end-marker)
      END_MARKER="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage
      ;;
    *)
      if [ -z "$FILE" ]; then
        FILE="$1"
      else
        printf 'Unexpected extra argument: %s\n' "$1" >&2
        usage
      fi
      shift
      ;;
  esac
done

[ -n "$FILE" ] || usage

if [ ! -f "$FILE" ]; then
  printf '[ERROR] file not found: %s\n' "$FILE" >&2
  exit 2
fi

case "$CEILING" in
  ''|*[!0-9]*)
    printf '[ERROR] --ceiling must be a positive integer, got: %s\n' "$CEILING" >&2
    exit 2
    ;;
esac

if ! grep -qF "$START_MARKER" "$FILE"; then
  printf '[ERROR] start marker not found in %s: %s\n' "$FILE" "$START_MARKER" >&2
  exit 2
fi
if ! grep -qF "$END_MARKER" "$FILE"; then
  printf '[ERROR] end marker not found in %s: %s\n' "$FILE" "$END_MARKER" >&2
  exit 2
fi

# Extract the bytes strictly between the two markers (marker lines themselves
# excluded). awk -v handles literal marker strings safely (no regex escaping
# needed since we compare whole-line equality... but markers may share a line
# with other text in adversarial fixtures, so match by substring instead).
REGION_FILE="$(mktemp)"
trap 'rm -f "$REGION_FILE"' EXIT

awk -v s="$START_MARKER" -v e="$END_MARKER" '
  index($0, s) > 0 { inblk = 1; next }
  index($0, e) > 0 { inblk = 0; next }
  inblk { print }
' "$FILE" > "$REGION_FILE"

CHAR_COUNT="$(wc -c < "$REGION_FILE" | tr -d '[:space:]')"

# ceil(a/b) without bc/python — pure integer arithmetic (bash 3.2 safe).
PROXY_COUNT=$(( (CHAR_COUNT + 3) / 4 ))

printf '[token-budget] %s: always-loaded region = %s chars, proxy(chars/4, ceil) = %s tokens (ceiling %s)\n' \
  "$FILE" "$CHAR_COUNT" "$PROXY_COUNT" "$CEILING" >&2

if [ "$PROXY_COUNT" -gt "$CEILING" ]; then
  printf '[FAIL] always-loaded region proxy token count %s exceeds ceiling %s\n' "$PROXY_COUNT" "$CEILING" >&2
  exit 1
fi

printf '[PASS] always-loaded region proxy token count %s <= ceiling %s\n' "$PROXY_COUNT" "$CEILING" >&2
exit 0
