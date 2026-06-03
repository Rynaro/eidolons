#!/usr/bin/env bash
# eidolons verify-envelope — mechanical ECL hand-off integrity gate
# ═══════════════════════════════════════════════════════════════════════════
# A DETERMINISTIC, non-LLM SHA-256 verifier for ECL hand-off envelopes. This is
# the trust anchor for inter-Eidolon hand-offs (R3-09: a shasum compare in bash,
# never a judging Eidolon). It is Eidolon-agnostic — ANY receiver (or the
# orchestrator, as a `eidolons run --verify` pre-step) runs the SAME gate, which
# is what makes the verification SYMMETRIC instead of APIVR-only.
#
# Modes (staged rollout per ECL v1.0 opt-in P0):
#   warn  (default) — report a mismatch but exit 0 (payload may still be used).
#   block          — refuse on mismatch (exit 3), enforcing ECL §6.2.2
#                    "receiver SHALL NOT process on integrity mismatch".
# Set the default per project via EIDOLONS_ECL_VERIFY_MODE=block, or per call
# with --block / --mode block. The intended path is warn for one release, then
# flip the default to block.
#
# Version note (reconciles gap V3): an envelope carries envelope_version "2.0"
# (the WIRE format), the ECL SPEC is at v1.0, and artifact.schema_version is the
# ARTIFACT schema — three distinct layers. This gate accepts envelope_version
# 2.0 and warns (does not fail) on any other wire version.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<EOF
eidolons verify-envelope — mechanically verify an ECL hand-off envelope

Usage: eidolons verify-envelope <envelope.json> [OPTIONS]

Recomputes the SHA-256 of the referenced payload and compares it to the
envelope's integrity tag (no LLM, no eval). The payload is resolved from
artifact.path relative to the envelope's directory.

Options:
  --mode warn|block   Failure handling (default: warn, or \$EIDOLONS_ECL_VERIFY_MODE)
  --block             Shorthand for --mode block (enforce ECL §6.2.2)
  --trace <file>      Append a JSONL verify_pass/verify_fail event to <file>
  --json              Emit the verdict as JSON
  -h, --help          Show this help

Verdicts: pass · tamper · inconsistent · unverifiable · missing_payload
          · unsupported_algo · malformed
Exit:  0 pass (or warn-mode non-pass) · 2 malformed/usage · 3 blocked failure
EOF
}

ENVELOPE=""
MODE="${EIDOLONS_ECL_VERIFY_MODE:-warn}"
TRACE=""
OUT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)   MODE="${2:-warn}"; shift 2 ;;
    --block)  MODE="block"; shift ;;
    --trace)  TRACE="${2:-}"; shift 2 ;;
    --json)   OUT="json"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)       die "Unknown option: $1 (see 'eidolons verify-envelope --help')" ;;
    *)        ENVELOPE="$1"; shift ;;
  esac
done

[[ -n "$ENVELOPE" ]] || die "No envelope given. Usage: eidolons verify-envelope <envelope.json>"
case "$MODE" in warn|block) ;; *) die "Invalid --mode '$MODE' (want warn|block)" ;; esac

# ── emit(verdict, message, [expected], [actual]) — render + trace + exit ──────
_blocked=false
emit() {
  local verdict="$1" message="$2" expected="${3:-}" actual="${4:-}"
  local from to perf eid_ver
  from="$(jq -r '.from.eidolon // "?"' "$ENVELOPE" 2>/dev/null || echo "?")"
  to="$(jq -r '.to.eidolon // "?"' "$ENVELOPE" 2>/dev/null || echo "?")"
  perf="$(jq -r '.performative // "?"' "$ENVELOPE" 2>/dev/null || echo "?")"

  # Decide blocking: only genuine integrity failures block, and only in block mode.
  case "$verdict" in
    tamper|inconsistent|missing_payload|unsupported_algo)
      [[ "$MODE" == "block" ]] && _blocked=true ;;
    malformed) ;;  # handled with exit 2 directly by callers
  esac

  # Optional JSONL trace event (ECL trace stream).
  if [[ -n "$TRACE" ]]; then
    local ev="verify_fail"; [[ "$verdict" == "pass" ]] && ev="verify_pass"
    local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")"
    jq -nc --arg ev "$ev" --arg verdict "$verdict" --arg ts "$ts" \
      --arg env "$ENVELOPE" --arg mode "$MODE" --arg from "$from" --arg to "$to" \
      '{event:$ev, verdict:$verdict, ts:$ts, envelope:$env, mode:$mode, from:$from, to:$to, verifier:"eidolons"}' \
      >> "$TRACE" 2>/dev/null || true
  fi

  if [[ "$OUT" == "json" ]]; then
    jq -nc --arg verdict "$verdict" --arg mode "$MODE" --argjson blocked "$_blocked" \
      --arg env "$ENVELOPE" --arg from "$from" --arg to "$to" --arg perf "$perf" \
      --arg expected "$expected" --arg actual "$actual" --arg message "$message" \
      '{verdict:$verdict, mode:$mode, blocked:$blocked, envelope:$env, from:$from, to:$to,
        performative:$perf, expected_sha:$expected, actual_sha:$actual, message:$message}'
  else
    local glyph color
    case "$verdict" in
      pass)         glyph="${GLYPH_OK:-OK}";   color="${UI_OK:-}" ;;
      unverifiable) glyph="${GLYPH_WARN:-!}";  color="${UI_WARN:-}" ;;
      *)            glyph="${GLYPH_ERROR:-x}"; color="${UI_ERROR:-}" ;;
    esac
    printf '%s%s%s ecl verify [%s] %s → %s (%s): %s\n' \
      "$color" "$glyph" "${RESET:-}" "$verdict" "$from" "$to" "$perf" "$message" >&2
  fi

  if [[ "$_blocked" == true ]]; then
    exit 3
  fi
  [[ "$verdict" == "pass" || "$verdict" == "unverifiable" ]] && exit 0
  exit 0  # warn mode: non-pass is surfaced but not blocking
}

# ── 1. Envelope is readable + valid JSON ──────────────────────────────────────
[[ -f "$ENVELOPE" ]] || die "Envelope not found: $ENVELOPE"
if ! jq empty "$ENVELOPE" >/dev/null 2>&1; then
  if [[ "$OUT" == "json" ]]; then
    jq -nc --arg env "$ENVELOPE" '{verdict:"malformed", message:"not valid JSON", envelope:$env}'
  else
    warn "ecl verify [malformed] $ENVELOPE: not valid JSON"
  fi
  exit 2
fi

# ── 2. Required fields ────────────────────────────────────────────────────────
_missing="$(jq -r '
  [ if .envelope_version == null then "envelope_version" else empty end,
    if (.from.eidolon // null) == null then "from.eidolon" else empty end,
    if (.to.eidolon // null) == null then "to.eidolon" else empty end,
    if .performative == null then "performative" else empty end,
    if (.artifact.path // null) == null then "artifact.path" else empty end,
    if (.integrity.method // null) == null then "integrity.method" else empty end,
    if (.integrity.value // null) == null then "integrity.value" else empty end ]
  | join(", ")' "$ENVELOPE" 2>/dev/null)"
if [[ -n "$_missing" ]]; then
  if [[ "$OUT" == "json" ]]; then
    jq -nc --arg env "$ENVELOPE" --arg m "$_missing" '{verdict:"malformed", message:("missing required fields: "+$m), envelope:$env}'
  else
    warn "ecl verify [malformed] $ENVELOPE: missing required fields: $_missing"
  fi
  exit 2
fi

EV_VERSION="$(jq -r '.envelope_version' "$ENVELOPE")"
# Advisory warnings go to stderr only in text mode — never pollute --json stdout.
if [[ "$EV_VERSION" != "2.0" && "$OUT" != "json" ]]; then
  warn "ecl verify: unrecognized envelope_version '$EV_VERSION' (expected 2.0) — proceeding"
fi

# ── 3. Algorithm ──────────────────────────────────────────────────────────────
METHOD="$(jq -r '.integrity.method' "$ENVELOPE")"
[[ "$METHOD" == "sha256" ]] || emit "unsupported_algo" "integrity.method '$METHOD' is not sha256"

INTEGRITY_VALUE="$(jq -r '.integrity.value' "$ENVELOPE")"
ARTIFACT_SHA="$(jq -r '.artifact.sha256 // ""' "$ENVELOPE")"

# ── 4. Placeholder guard (parent-fills-SHA pattern) ───────────────────────────
# The orchestrator patches artifact.sha256 + integrity.value post-handoff; never
# fail an unfilled envelope — report it as unverifiable so the parent fills it.
case "$INTEGRITY_VALUE" in
  ""|PARENT_FILLS_*|"<"*|"TODO"*|null)
    emit "unverifiable" "integrity.value is a placeholder ('$INTEGRITY_VALUE') — parent must fill the SHA before verification" ;;
esac

# ── 5. Internal consistency: integrity.value vs artifact.sha256 ──────────────
if [[ -n "$ARTIFACT_SHA" && "$ARTIFACT_SHA" != "$INTEGRITY_VALUE" ]]; then
  emit "inconsistent" "artifact.sha256 != integrity.value (envelope self-inconsistent)" "$INTEGRITY_VALUE" "$ARTIFACT_SHA"
fi

# ── 6. Resolve payload + recompute SHA-256 (the tamper check) ────────────────
ART_PATH="$(jq -r '.artifact.path' "$ENVELOPE")"
ENV_DIR="$(cd "$(dirname "$ENVELOPE")" && pwd)"
PAYLOAD="$ENV_DIR/$ART_PATH"
# Fallback to the sibling convention <payload>.envelope.json if artifact.path
# does not resolve (e.g. the envelope was moved without its declared sibling).
if [[ ! -f "$PAYLOAD" ]]; then
  _sibling="${ENVELOPE%.envelope.json}"
  [[ -f "$_sibling" ]] && PAYLOAD="$_sibling"
fi
[[ -f "$PAYLOAD" ]] || emit "missing_payload" "payload not found at artifact.path '$ART_PATH' (resolved: $PAYLOAD)"

ACTUAL_SHA="$(sha256_file "$PAYLOAD")"

# Optional size cross-check (advisory).
DECLARED_SIZE="$(jq -r '.artifact.size_bytes // ""' "$ENVELOPE")"
if [[ -n "$DECLARED_SIZE" && "$OUT" != "json" ]]; then
  ACTUAL_SIZE="$(wc -c < "$PAYLOAD" | tr -d '[:space:]')"
  [[ "$DECLARED_SIZE" == "$ACTUAL_SIZE" ]] || warn "ecl verify: size_bytes mismatch (declared $DECLARED_SIZE, actual $ACTUAL_SIZE)"
fi

# ── 7. Verdict ────────────────────────────────────────────────────────────────
if [[ "$ACTUAL_SHA" == "$INTEGRITY_VALUE" ]]; then
  emit "pass" "payload SHA-256 matches integrity tag" "$INTEGRITY_VALUE" "$ACTUAL_SHA"
else
  emit "tamper" "payload SHA-256 does NOT match integrity tag — possible tampering or stale envelope" "$INTEGRITY_VALUE" "$ACTUAL_SHA"
fi
