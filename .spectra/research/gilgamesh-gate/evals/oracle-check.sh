#!/usr/bin/env bash
# evals/oracle-check.sh — mechanical Arm-1 (capability-expansion) report grader.
#
# ESL change generalist-eidolon, Track G (R-039/AC-G01). Gate author:
# gate-author-sonnet-fresh (identity distinct from ramza/vivi/generalist-builder;
# does NOT assign ground-truth labels — that is Arm-2's independent labeler,
# AC-G07 — this script only grades Arm-1 mechanical facts).
#
# Grades one gilgamesh (or any candidate generalist) mission report against
# the frozen oracle_expected block for that mission id in arm1-holdout.jsonl:
#   - every required ANSWER-<key> line is present and matches EXACTLY (trimmed)
#   - every required VERIFY-<name> line is present and matches EXACTLY
#   - every required EVIDENCE-<key> line is present and its "path:line"
#     anchor actually resolves (file exists, sed -n '<line>p' is non-empty)
#   - a PROPOSAL + PROPOSAL-TARGET pair is present and PROPOSAL-TARGET resolves
#
# This script does NOT judge whether the cited evidence is semantically
# correct beyond resolving — that would require a human/LLM judge, which is
# explicitly out of scope for a mechanical gate (see spec.md Track G, "maker
# cannot cherry-pick" — this grader must be re-runnable by a third party with
# no discretion).
#
# Usage:
#   oracle-check.sh <mission-id> <report-file>
#
# Exit codes:
#   0 — all required fields present, exact, and evidence anchors resolve
#   1 — one or more mechanical checks failed (failures listed on stderr)
#   2 — usage error / mission id not found / report file not found
#
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_DIR="$(cd "$SELF_DIR/.." && pwd)"
NEXUS_ROOT="${NEXUS_ROOT:-$(cd "$GATE_DIR/../../.." && pwd)}"
HOLDOUT="${HOLDOUT:-$GATE_DIR/arm1-holdout.jsonl}"

if [ "$#" -lt 2 ]; then
  printf 'Usage: %s <mission-id> <report-file>\n' "$(basename "$0")" >&2
  exit 2
fi

MISSION_ID="$1"
REPORT_FILE="$2"

if [ ! -f "$HOLDOUT" ]; then
  printf '[ERROR] holdout file not found: %s\n' "$HOLDOUT" >&2
  exit 2
fi
if [ ! -f "$REPORT_FILE" ]; then
  printf '[ERROR] report file not found: %s\n' "$REPORT_FILE" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '[ERROR] jq is required\n' >&2
  exit 2
fi

RECORD="$(jq -c --arg id "$MISSION_ID" 'select(.id == $id)' "$HOLDOUT")"
if [ -z "$RECORD" ]; then
  printf '[ERROR] mission id not found in holdout: %s\n' "$MISSION_ID" >&2
  exit 2
fi

fail=0
note() { printf '[FAIL] %s\n' "$1" >&2; fail=1; }

# Fetch a report line by its exact label, e.g. "ANSWER-enum_count" -> value
# after the first ':' , trimmed of surrounding whitespace. Empty if absent.
report_value() {
  # $1 = label (without trailing colon)
  grep -m1 "^${1}:" "$REPORT_FILE" 2>/dev/null \
    | sed -E "s/^${1}:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' \
    || true
}

# ── ANSWER-* exact-match checks ─────────────────────────────────────────────
while IFS=$'\t' read -r key expected; do
  [ -z "$key" ] && continue
  got="$(report_value "$key")"
  if [ -z "$got" ]; then
    note "missing report line: ${key}: <value>"
  elif [ "$got" != "$expected" ]; then
    note "${key}: expected exact match '${expected}', got '${got}'"
  fi
done <<EOF_ANSWERS
$(printf '%s' "$RECORD" | jq -r '.oracle_expected.answers | to_entries[] | [.key, .value] | @tsv')
EOF_ANSWERS

# ── VERIFY-* exact-match checks ─────────────────────────────────────────────
while IFS=$'\t' read -r key expected; do
  [ -z "$key" ] && continue
  got="$(report_value "$key")"
  if [ -z "$got" ]; then
    note "missing report line: ${key}: pass|fail"
  elif [ "$got" != "$expected" ]; then
    note "${key}: expected '${expected}', got '${got}'"
  fi
done <<EOF_VERIFIES
$(printf '%s' "$RECORD" | jq -r '.oracle_expected.verifies | to_entries[] | [.key, .value] | @tsv')
EOF_VERIFIES

# ── EVIDENCE-* anchor-resolution checks (path:line, sed -n spot-check) ─────
resolve_anchor() {
  # $1 = "path:line" (path may itself contain ':', so split on the LAST ':')
  anchor="$1"
  line="${anchor##*:}"
  path="${anchor%:*}"
  case "$line" in
    ''|*[!0-9]*) note "evidence anchor has a non-numeric line: ${anchor}"; return ;;
  esac
  full="$NEXUS_ROOT/$path"
  if [ ! -f "$full" ]; then
    note "evidence path does not exist: ${path} (from anchor ${anchor})"
    return
  fi
  spot="$(sed -n "${line}p" "$full" 2>/dev/null || true)"
  if [ -z "$spot" ]; then
    note "evidence line does not resolve (empty/out-of-range): ${anchor}"
  fi
}

while IFS= read -r key; do
  [ -z "$key" ] && continue
  got="$(report_value "$key")"
  if [ -z "$got" ]; then
    note "missing required evidence line: ${key}: <path:line>"
  else
    resolve_anchor "$got"
  fi
done <<EOF_EVIDENCE
$(printf '%s' "$RECORD" | jq -r '.oracle_expected.evidence_keys_required[]?')
EOF_EVIDENCE

# ── PROPOSAL / PROPOSAL-TARGET (always required per requires_proposal) ─────
requires_proposal="$(printf '%s' "$RECORD" | jq -r '.oracle_expected.requires_proposal')"
if [ "$requires_proposal" = "true" ]; then
  proposal="$(report_value "PROPOSAL")"
  if [ -z "$proposal" ]; then
    note "missing required line: PROPOSAL: <one-line text>"
  fi
  target="$(report_value "PROPOSAL-TARGET")"
  if [ -z "$target" ]; then
    note "missing required line: PROPOSAL-TARGET: <path:line>"
  else
    resolve_anchor "$target"
  fi
fi

if [ "$fail" -eq 0 ]; then
  printf '[PASS] %s: all mechanical checks green\n' "$MISSION_ID"
  exit 0
else
  printf '[FAIL] %s: one or more mechanical checks failed (see above)\n' "$MISSION_ID" >&2
  exit 1
fi
