#!/usr/bin/env bash
# verify-recall-mutation.sh — prove the recall suite CAN fail (ESL AC-5).
#
# A benchmark shipped in the same commit as the data it measures passes
# trivially. `evals/routing-suite.yaml`'s `public` arm was authored FROM the
# trigger lexicons in roster/routing.yaml, sat at 15/15 = 100%, and stayed
# green while the router scored zero on 91% of ordinary engineering prompts.
#
# This script guards the replacement against becoming the same tautology: it
# runs the CURRENT recall suite against a PRIOR roster/routing.yaml and asserts
# the score collapses. If it does not collapse, the suite is no longer
# measuring the lexicon and must be rewritten — do NOT relax the ceiling.
#
# Usage:  scripts/verify-recall-mutation.sh [git-ref] [max-percent]
#   git-ref      revision to take roster/routing.yaml from (default: HEAD~1)
#   max-percent  fail if recall at/above this (default: 20)
#
# bash 3.2 compatible (macOS system shell).
set -u

REF="${1:-HEAD~1}"
MAX="${2:-20}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if ! git rev-parse --verify "$REF" >/dev/null 2>&1; then
  echo "verify-recall-mutation: unknown git ref '$REF'" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Current tree (new suite, new kernel) …
tar --exclude=.git -cf - cli roster evals schemas methodology VERSION 2>/dev/null \
  | tar -C "$TMP" -xf - || exit 2
# … with ONLY the routing data reverted.
git show "${REF}:roster/routing.yaml" > "$TMP/roster/routing.yaml" || exit 2

echo "── recall suite (current) vs roster/routing.yaml @ ${REF} ──"
OUT="$(EIDOLONS_NEXUS="$TMP" bash "$TMP/cli/eidolons" eval routing --suite recall 2>&1)"
printf '%s\n' "$OUT"

# Take the field that ENDS IN '%', not a fixed column. The OVERALL line is
#   OVERALL   8/49   16.3%   cost=0 tokens (no model)
# and a positional $4 grabs "cost=0", which awk then happily reads as 0 —
# a gate that passes for the wrong reason on every input. (It did exactly
# that on first run; found by checking the message, not the exit status.)
PCT="$(printf '%s\n' "$OUT" | awk '/OVERALL/ {for (i=1;i<=NF;i++) if ($i ~ /%$/) {gsub(/%/,"",$i); print $i; exit}}')"
if [ -z "${PCT:-}" ]; then
  echo "verify-recall-mutation: could not parse OVERALL percentage" >&2
  exit 2
fi

echo
if awk "BEGIN{exit !($PCT < $MAX)}"; then
  echo "PASS — recall collapses to ${PCT}% against ${REF} (< ${MAX}%): the suite can fail."
  exit 0
fi

echo "FAIL — recall stayed at ${PCT}% against ${REF} (>= ${MAX}%)." >&2
echo "The recall suite is no longer sensitive to the lexicon it exists to measure." >&2
echo "Rewrite the suite intent-first. Do NOT raise the ceiling to make this pass." >&2
exit 1
