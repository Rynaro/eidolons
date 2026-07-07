#!/usr/bin/env bash
# cli/src/lib_context.sh — shared helpers for the 'eidolons context' verb
# family (ECM P1 — context-lifecycle kernel).
#
# Sourced by: context.sh, context_status.sh, context_policy.sh,
#             context_externalize.sh, context_handoff.sh.
#
# Convention (mirrors lib_memory_probe.sh): every function here is silent
# (return code / stdout value only) — no info/warn/pass/err calls. Each call
# site owns its own messaging so wording stays under that call site's tests,
# not this file's.
#
# Bash 3.2 safe: no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# See CLAUDE.md §"Bash 3.2 compatibility".

# ─── Named constants (spec §3.1, D1) ───────────────────────────────────────
# The bytes/token divisor is a NAMED constant (not inlined) so the D1
# divisor-bias canary measurement can flip it (4 -> 3.5) without a code hunt.
: "${ECM_BYTES_PER_TOKEN:=4}"
export ECM_BYTES_PER_TOKEN

# Default context window size (tokens) when no host telemetry supplies one.
: "${ECM_DEFAULT_WINDOW_TOKENS:=200000}"
export ECM_DEFAULT_WINDOW_TOKENS

# Zone boundaries (spec §3.1 / roster/context-policy.yaml zones:) — coarse
# 25-point bands so a +/-10% estimate cannot mis-zone by more than one band.
: "${ECM_ZONE_AMBER:=0.50}"
: "${ECM_ZONE_RED:=0.75}"
: "${ECM_ZONE_CRITICAL:=0.90}"
export ECM_ZONE_AMBER ECM_ZONE_RED ECM_ZONE_CRITICAL

# crystalium call budget (ms) — 1.5s timeout -> skip, never block (CC2).
: "${ECM_MEMORY_TIMEOUT_S:=1.5}"
export ECM_MEMORY_TIMEOUT_S

# ─── Sidecar directory ──────────────────────────────────────────────────────
# .eidolons/.context/ is covered by the existing blanket .gitignore rule
# (FINDING-027) — no .gitignore change needed.
ECM_SIDECAR_DIR=".eidolons/.context"

# context_sidecar_dir [PROJECT_ROOT] — echo the sidecar dir path and ensure
# it exists (best-effort; fail-soft variant per FINDING-026).
context_sidecar_dir() {
  local root="${1:-.}"
  local dir="$root/$ECM_SIDECAR_DIR"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}

# context_meter_path [PROJECT_ROOT] [SESSION_ID] [SUBAGENT(0|1)]
# D3: the orchestrator/main session always uses meter.json; a subagent
# session (SUBAGENT=1) gets its OWN file keyed by session id.
context_meter_path() {
  local root="${1:-.}" session_id="${2:-}" subagent="${3:-0}"
  local dir
  dir="$(context_sidecar_dir "$root")"
  if [ "$subagent" = "1" ] && [ -n "$session_id" ]; then
    printf '%s/meter-%s.json' "$dir" "$session_id"
  else
    printf '%s/meter.json' "$dir"
  fi
}

# context_zone_of UTILIZATION — echo green|amber|red|critical|unknown.
# UTILIZATION empty/non-numeric -> unknown (D1 rung-3 fail-open floor, CC2).
context_zone_of() {
  local util="${1:-}"
  case "$util" in
    ''|*[!0-9.]*) printf 'unknown'; return 0 ;;
  esac
  awk -v u="$util" -v amber="$ECM_ZONE_AMBER" -v red="$ECM_ZONE_RED" -v crit="$ECM_ZONE_CRITICAL" '
    BEGIN {
      if (u >= crit) print "critical";
      else if (u >= red) print "red";
      else if (u >= amber) print "amber";
      else print "green";
    }'
}

# context_now_iso8601 — UTC ISO-8601 timestamp (portable GNU/BSD date).
context_now_iso8601() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ'
}

# context_now_epoch_ts — filename-safe timestamp token (epoch seconds).
context_now_epoch_ts() {
  date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || date '+%s'
}

# context_sha256_string STR — sha256 of STR (portable shasum/sha256sum).
context_sha256_string() {
  local s="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$s" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha256sum | awk '{print $1}'
  else
    printf ''
  fi
}

# context_sha256_file PATH — sha256 of a file's contents.
context_sha256_file() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  else
    printf ''
  fi
}

# context_bytes_to_tokens BYTES — echo BYTES / ECM_BYTES_PER_TOKEN (integer,
# floor) via awk (bash 3.2 has no floating-point arithmetic builtin).
context_bytes_to_tokens() {
  local bytes="${1:-0}"
  awk -v b="$bytes" -v d="$ECM_BYTES_PER_TOKEN" 'BEGIN { printf "%d", (b / d) }'
}

# context_policy_file — echo the nexus-shipped policy file path, mirroring
# run.sh's ROUTING_FILE derivation from ROSTER_FILE (lib.sh).
context_policy_file() {
  printf '%s/context-policy.yaml' "$(dirname "$ROSTER_FILE")"
}

# context_pins_file — echo the nexus-shipped default pin-set file path.
context_pins_file() {
  printf '%s/pins.yaml' "$(dirname "$ROSTER_FILE")"
}

# context_json_array ARG... — echo a JSON array of string args ([] if none).
# Bash 3.2 safe (no associative arrays; plain positional args only).
context_json_array() {
  if [ "$#" -eq 0 ]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || printf '[]'
}

# context_try_ingest PROJECT_ROOT ENVELOPE_JSON PAYLOAD_TEXT
#
# One-shot crystalium_ingest attempt via the docker one-shot transform
# (FINDING-011/012), mirroring memory.sh/canary.sh's proven `commit`/`recall`
# shape. [ASSUMPTION/GAP-D5-ingest]: the exact one-shot CLI `ingest` verb
# shape is unconfirmed in-repo; this is a best-effort extension of the
# proven pattern. Requires lib_memory_probe.sh to already be sourced by the
# caller. Returns 0 on an apparent success (docker exit 0), 1 otherwise.
# NEVER a fallback to `commit` — callers must not chain one after this fails
# (AC-16: crystalium_ingest is the canonical persist path, no commit branch).
context_try_ingest() {
  local project_root="$1" envelope_json="$2" payload_text="$3"

  command -v docker >/dev/null 2>&1 || return 1

  local q_envelope q_payload ingest_args script exit_code=0
  q_envelope="$(memory_probe_quote "$envelope_json")"
  q_payload="$(memory_probe_quote "$payload_text")"
  ingest_args="ingest --envelope $q_envelope --payload $q_payload --payload-encoding utf8 --format json"

  script="$(mktemp)"
  if ! memory_probe_build_docker_script "$project_root" "$ingest_args" "$script"; then
    rm -f "$script"
    return 1
  fi

  with_timeout "$ECM_MEMORY_TIMEOUT_S" bash "$script" >/dev/null 2>&1 || exit_code=$?
  rm -f "$script"
  [ "$exit_code" -eq 0 ]
}
