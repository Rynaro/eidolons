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
#   git-ref      revision to take roster/routing.yaml from
#                (default: v2.17.0 — the last release BEFORE the lexicons were
#                widened, so the comparison is meaningful from any checkout)
#   max-percent  fail if the recall arm scores at/above this (default: 20)
#
# The default was HEAD~1, which is only correct while standing on the merge
# commit; run from main a release later it compares against an already-fixed
# routing.yaml, reports 100%, and prints a FAIL telling you to rewrite a suite
# that is fine. A pinned pre-change tag has no such footgun.
#
# bash 3.2 compatible (macOS system shell).
set -u

REF="${1:-v2.17.0}"
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

# Score the RECALL ARM only — every category NOT named `guard-*`.
#
# Guards are precision tasks: they assert a prompt still clarifies, still
# reroutes on refusal, still reaches a read-only member. They are SUPPOSED to
# pass against both the old and the new lexicons, so including them puts a
# floor under the mutated score that rises with every guard added. When the
# guard set grew 5 -> 10 the OVERALL figure went 16.6% -> 22% and tripped this
# gate — not because the suite got weaker, but because the instrument was
# measuring the wrong population. Fixing that is the honest move; RAISING THE
# CEILING to make it pass would be the gate-that-cannot-fail defect this script
# exists to prevent, committed by the script itself.
JSON="$(EIDOLONS_NEXUS="$TMP" bash "$TMP/cli/eidolons" eval routing --suite recall --json 2>/dev/null)"
PCT="$(printf '%s' "$JSON" | jq -r '
  [ .by_category[] | select(.category | startswith("guard-") | not) ] as $r
  | if ($r | length) == 0 then "" else
      (( [$r[].passed] | add ) * 100 / ( [$r[].total] | add ) | . * 10 | round / 10 | tostring)
    end' 2>/dev/null)"
if [ -z "${PCT:-}" ] || [ "$PCT" = "null" ]; then
  echo "verify-recall-mutation: could not compute the non-guard recall score" >&2
  exit 2
fi
echo "recall arm (guards excluded): ${PCT}%"

echo
if awk "BEGIN{exit !($PCT < $MAX)}"; then
  echo "PASS — recall collapses to ${PCT}% against ${REF} (< ${MAX}%): the suite can fail."
  exit 0
fi

echo "FAIL — recall stayed at ${PCT}% against ${REF} (>= ${MAX}%)." >&2
echo "The recall suite is no longer sensitive to the lexicon it exists to measure." >&2
echo "Rewrite the suite intent-first. Do NOT raise the ceiling to make this pass." >&2
exit 1
