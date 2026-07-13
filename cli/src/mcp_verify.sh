#!/usr/bin/env bash
# cli/src/mcp_verify.sh — verify wired reality (.mcp.json) against locked
# intent (eidolons.mcp.lock). The DETECTOR half of ESL change
# mcp-verify-lock-vs-artifact (F1: the lock is intent, .mcp.json is effect;
# 'verify' reports both and NEVER repairs — the repair already exists as
# 'mcp install <name>@<ver> --force').
#
# Usage: eidolons mcp verify [<name>] [--json] [--strict] [--probe]
#                             [--project-root PATH]
#
# Exit codes (F2 — non-zero on mismatch, doctor goes RED in the fast checks):
#   0  verified (WARN findings may be present)
#   1  >=1 BLOCK finding — the host is not serving what the lock claims
#   2  usage error
#   3  INDETERMINATE — could not verify (no .mcp.json, unreadable catalogue,
#      no jq). NOT a pass. --strict promotes 3 -> 1.
#
# 'verify' executes NOTHING — no docker, no network, no subprocess beyond jq
# (F4). That property is what makes it safe to run against an untrusted checkout.
# --probe (a live tools/list probe, V-PROBE-SURFACE) is not implemented in this
# release and is a hard usage error rather than an accepted no-op — see the
# parser. A check that cannot run is never scored as a pass.
#
# stdout/stderr P0 (R11): all say/ok/info/warn/die go to stderr. stdout is
# reserved for the human table (plain mode) or the JSON report (--json mode).
# `eidolons mcp verify --json 2>/dev/null | jq empty` MUST pass.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile,
# no &>>. See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

usage() {
  cat >&2 <<EOF
eidolons mcp verify — verify wired reality (.mcp.json) against locked intent

Usage: eidolons mcp verify [<name>] [--json] [--strict] [--probe] [--project-root PATH]

Arguments:
  name                 Verify only this MCP (default: every catalogue-known
                        name in the lock, plus any catalogue-known server
                        wired in .mcp.json without a lock entry).

Options:
  --json                Emit a JSON report ({findings: [...], summary: {...}}).
  --strict              Promote INDETERMINATE and advisory findings that name
                         an unverifiable state (V-NOT-WIRED, V-UNPINNED-TAG) to
                         BLOCK. Never relaxes a check that is already BLOCK.
  --probe                Live tools/list probe (V-PROBE-SURFACE). NOT IMPLEMENTED
                         in this release: passing it is a usage error (exit 2),
                         deliberately, so it can never be mistaken for a pass.
  --project-root PATH   Resolve .mcp.json relative to PATH (default: cwd).
  -h, --help            Show this help.

What it checks (per lock entry):
  V-OCI-WIRED-MISMATCH        wired digest vs lock.integrity.value      BLOCK
  V-OCI-WIRED-MALFORMED       0 or >=2 distinct @sha256: refs wired     BLOCK
  V-LOCK-INCOHERENT           lock digest resolves to a DIFFERENT
                               published version than lock.version      BLOCK
  V-LOCK-UNPUBLISHED-DIGEST   lock digest matches no published release  WARN
  V-LOCK-PLACEHOLDER          lock digest is the all-zeros placeholder  BLOCK
  V-NOT-WIRED                 locked but .mcp.json absent/unreadable/
                               missing the entry with no sibling wired  INDET
                               (--strict: BLOCK)
  V-PARTIALLY-WIRED           locked, absent from .mcp.json, but other
                               eidolons servers ARE present              WARN
  V-UNLOCKED-SERVER           catalogue-known server wired, no lock      WARN
  V-UNPINNED-TAG              wired ref is a mutable tag, not a digest   WARN
                               (--strict: BLOCK)
  V-BIN-WIRED-MISMATCH        .mcp.json command vs lock.target          BLOCK
  V-BIN-TARGET-MISSING        lock.target missing or not executable     BLOCK

'verify' NEVER repairs. On a finding it prints the remedy command and stops —
the repair already exists: eidolons mcp install <name>@<ver> --force
EOF
}

JSON=false
STRICT=false
PROJECT_ROOT=""
NAME_FILTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --json)   JSON=true; shift ;;
    --strict) STRICT=true; shift ;;
    # --probe (F4 / E): V-PROBE-SURFACE is NOT implemented in this release (filed
    # as a follow-up; its systematic form belongs in nexus CI at digest-bump time).
    # It is a hard usage error, NOT an accepted no-op — and it fails HERE, before
    # any report is emitted, so no caller can read a verdict that omitted it.
    #
    # An earlier draft accepted the flag and merely info'd, reasoning that this
    # kept it "forward-compatible for scripts written against the eventual
    # implementation". That is the exact defect this whole change exists to kill:
    # the note goes to STDERR, which CI routinely discards, so `mcp verify --probe`
    # would exit 0 on a clean project and read as "the served tool surface was
    # verified" when nothing was probed at all. A check that cannot run must never
    # be scored as a pass — least of all by the verb whose entire job is enforcing
    # that rule. When the probe lands the flag simply starts working, and no caller
    # has been silently lied to in the meantime.
    --probe)
      printf 'eidolons mcp verify: --probe (V-PROBE-SURFACE) is not implemented in this release.\n' >&2
      printf '  It would execute each server and compare its live tools/list against the\n' >&2
      printf '  catalogue. Refusing to exit 0 as though the surface had been verified.\n' >&2
      printf '  Re-run without --probe to check wiring integrity (digest/path axes).\n' >&2
      exit 2
      ;;
    --project-root)
      [ -z "${2:-}" ] && { echo "--project-root requires an argument" >&2; exit 2; }
      PROJECT_ROOT="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      if [ -n "$NAME_FILTER" ]; then
        printf 'Unexpected argument: %s\n' "$1" >&2
        exit 2
      fi
      NAME_FILTER="$1"
      shift
      ;;
  esac
done

if [ -n "$NAME_FILTER" ]; then
  # Validate the name against the catalogue up front (consistent with the
  # rest of the mcp verb family — an unknown name is a usage error).
  _kind_check="$(mcp_catalogue_get_field "$NAME_FILTER" '.kind')"
  [ -n "$_kind_check" ] || { printf "MCP '%s' not found in catalogue. Try: eidolons mcp list\n" "$NAME_FILTER" >&2; exit 2; }
fi

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" \
  || { printf 'project root does not exist: %s\n' "$PROJECT_ROOT" >&2; exit 2; }

MCP_JSON="${PROJECT_ROOT}/.mcp.json"

_BOOTSTRAP_PLACEHOLDER="sha256:0000000000000000000000000000000000000000000000000000000000000000"

# ─── Findings accumulator ────────────────────────────────────────────────────
# Bash-3.2-safe: a newline-delimited string of compact JSON objects (avoids
# indexed-array-under-`set -u` empty-array pitfalls). Slurped with `jq -s` at
# the end, which yields [] naturally on empty input.
FINDINGS_JSONL=""

_add_finding() {
  local id="$1" sev="$2" mcp="$3" msg="$4" remedy="${5:-}"
  local obj
  obj="$(jq -n \
    --arg id "$id" --arg sev "$sev" --arg mcp "$mcp" --arg msg "$msg" --arg rem "$remedy" \
    '{id:$id, severity:$sev, mcp:$mcp, message:$msg, remedy:(if $rem=="" then null else $rem end)}')"
  FINDINGS_JSONL="${FINDINGS_JSONL}${obj}
"
}

_name_in_list() {
  local needle="$1" list="$2" x
  while IFS= read -r x; do
    [ "$x" = "$needle" ] && return 0
  done <<< "$list"
  return 1
}

# ─── Global INDETERMINATE early-exits (no jq / no catalogue) ─────────────────
_emit_global_indeterminate() {
  local reason="$1"
  if [ "$JSON" = "true" ]; then
    local ec=3
    [ "$STRICT" = "true" ] && ec=1
    printf '{"findings":[],"summary":{"block":0,"warn":0,"indeterminate":1,"exit_code":%d},"indeterminate_reason":"%s"}\n' \
      "$ec" "$reason"
  else
    printf 'INDETERMINATE: %s\n' "$reason"
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  _emit_global_indeterminate "jq not found on PATH — cannot verify"
  [ "$STRICT" = "true" ] && exit 1
  exit 3
fi

CAT_FILE="$(mcp_catalogue_file)"
if [ ! -f "$CAT_FILE" ]; then
  _emit_global_indeterminate "MCP catalogue not found at ${CAT_FILE}"
  [ "$STRICT" = "true" ] && exit 1
  exit 3
fi

# ─── Read lock + wiring state ─────────────────────────────────────────────────
LOCK_JSON="$(mcp_lock_read)"
LOCK_NAMES="$(printf '%s' "$LOCK_JSON" | jq -r '(.mcps // [])[].name')"

MCP_JSON_ABSENT=true
MCP_JSON_VALID=false
if [ -f "$MCP_JSON" ]; then
  MCP_JSON_ABSENT=false
  if jq empty "$MCP_JSON" 2>/dev/null; then
    MCP_JSON_VALID=true
  fi
fi

# ─── Per-name checks ──────────────────────────────────────────────────────────

_verify_oci_entry() {
  local name="$1" lock_entry="$2" lock_version="$3"
  local lock_digest source_image
  lock_digest="$(printf '%s' "$lock_entry" | jq -r '.integrity.value // empty')"
  source_image="$(printf '%s' "$lock_entry" | jq -r '.source.image // empty')"
  [ -n "$source_image" ] || source_image="$(mcp_catalogue_get_field "$name" '.source.image')"

  # R5 — validate the lock on its own terms, independent of wiring.
  if [ -n "$lock_digest" ]; then
    if [ "$lock_digest" = "$_BOOTSTRAP_PLACEHOLDER" ]; then
      _add_finding "V-LOCK-PLACEHOLDER" "block" "$name" \
        "lock digest for '${name}' is still the all-zeros bootstrap placeholder." \
        "eidolons mcp install ${name}@${lock_version} --force (or --build-locally)"
    else
      local resolved_version
      resolved_version="$(mcp_catalogue_get "$name" \
        | jq -r --arg d "$lock_digest" '(.versions.releases // {}) | to_entries[] | select(.value.digest == $d) | .key' \
        | head -1)"
      if [ -z "$resolved_version" ]; then
        _add_finding "V-LOCK-UNPUBLISHED-DIGEST" "warn" "$name" \
          "lock digest for '${name}' (${lock_digest}) matches no published release in the catalogue (--build-locally is supported)." \
          ""
      elif [ "$resolved_version" != "$lock_version" ]; then
        _add_finding "V-LOCK-INCOHERENT" "block" "$name" \
          "lock claims version ${lock_version} for '${name}' but its digest (${lock_digest}) belongs to published version ${resolved_version} — the lock is internally inconsistent." \
          "eidolons mcp install ${name}@${resolved_version} --force"
      fi
    fi
  fi

  # R4/R6/R7 — wiring vs lock.
  if [ "$MCP_JSON_ABSENT" = "true" ] || [ "$MCP_JSON_VALID" = "false" ]; then
    local sev="indeterminate"
    [ "$STRICT" = "true" ] && sev="block"
    local reason="absent"
    [ "$MCP_JSON_ABSENT" = "false" ] && reason="not valid JSON"
    _add_finding "V-NOT-WIRED" "$sev" "$name" \
      "'${name}' is locked (version ${lock_version}) but .mcp.json is ${reason} — cannot confirm what is served." \
      "eidolons mcp install ${name}@${lock_version} --force"
    return 0
  fi

  local has_key
  has_key="$(jq -r --arg n "$name" '(.mcpServers // {}) | has($n)' "$MCP_JSON")"
  if [ "$has_key" != "true" ]; then
    _verify_orphan_not_wired "$name" "$lock_version"
    return 0
  fi

  # Distinct @sha256: digests wired for this entry.
  local digests distinct_count
  digests="$(jq -r --arg n "$name" \
    '(.mcpServers[$n].args // [])[] | select(type == "string" and test("@sha256:"))' \
    "$MCP_JSON" 2>/dev/null \
    | sed -n 's|.*@\(sha256:[0-9a-f]\{1,\}\).*|\1|p' \
    | sort -u)"
  distinct_count="$(printf '%s\n' "$digests" | grep -c '.' || true)"

  if [ "$distinct_count" -ge 2 ]; then
    _add_finding "V-OCI-WIRED-MALFORMED" "block" "$name" \
      "'${name}' server entry in .mcp.json references ${distinct_count} distinct @sha256: digests (expected exactly one)." \
      "eidolons mcp install ${name}@${lock_version} --force"
    return 0
  fi

  if [ "$distinct_count" -eq 0 ]; then
    local has_tag
    has_tag="$(jq -r --arg n "$name" --arg img "${source_image}:" \
      '(.mcpServers[$n].args // [])[] | select(type == "string" and startswith($img))' \
      "$MCP_JSON" 2>/dev/null | head -1)"
    if [ -n "$has_tag" ]; then
      local sev="warn"
      [ "$STRICT" = "true" ] && sev="block"
      _add_finding "V-UNPINNED-TAG" "$sev" "$name" \
        "'${name}' is wired with a mutable tag (${has_tag}), not a pinned digest — the wired-vs-locked digest comparison (R4) cannot be verified." \
        "eidolons mcp install ${name}@${lock_version} --force to re-pin to a digest"
    else
      _add_finding "V-OCI-WIRED-MALFORMED" "block" "$name" \
        "'${name}' server entry in .mcp.json has no @sha256: digest and no recognizable ${source_image}:<tag> reference." \
        "eidolons mcp install ${name}@${lock_version} --force"
    fi
    return 0
  fi

  # Exactly one digest wired: the actual R4 comparison.
  local wired_digest
  wired_digest="$(printf '%s\n' "$digests" | head -1)"
  if [ -n "$lock_digest" ] && [ "$wired_digest" != "$lock_digest" ]; then
    _add_finding "V-OCI-WIRED-MISMATCH" "block" "$name" \
      "'${name}' wired digest (${wired_digest}) != locked digest (${lock_digest})." \
      "eidolons mcp install ${name}@${lock_version} --force"
  fi
}

_verify_binary_entry() {
  local name="$1" lock_entry="$2" lock_version="$3"
  local lock_target
  lock_target="$(printf '%s' "$lock_entry" | jq -r '.target // empty')"

  # R8 — target existence + executable, independent of wiring.
  if [ -n "$lock_target" ]; then
    if [ ! -e "$lock_target" ] || [ ! -x "$lock_target" ]; then
      _add_finding "V-BIN-TARGET-MISSING" "block" "$name" \
        "lock target for '${name}' (${lock_target}) does not exist or is not executable." \
        "eidolons mcp install ${name}@${lock_version} --force"
    fi
  fi

  if [ "$MCP_JSON_ABSENT" = "true" ] || [ "$MCP_JSON_VALID" = "false" ]; then
    local sev="indeterminate"
    [ "$STRICT" = "true" ] && sev="block"
    local reason="absent"
    [ "$MCP_JSON_ABSENT" = "false" ] && reason="not valid JSON"
    _add_finding "V-NOT-WIRED" "$sev" "$name" \
      "'${name}' is locked (version ${lock_version}) but .mcp.json is ${reason} — cannot confirm what is served." \
      "eidolons mcp install ${name}@${lock_version} --force"
    return 0
  fi

  local has_key
  has_key="$(jq -r --arg n "$name" '(.mcpServers // {}) | has($n)' "$MCP_JSON")"
  if [ "$has_key" != "true" ]; then
    _verify_orphan_not_wired "$name" "$lock_version"
    return 0
  fi

  local wired_command
  wired_command="$(jq -r --arg n "$name" '.mcpServers[$n].command // empty' "$MCP_JSON")"
  if [ -n "$lock_target" ] && [ "$wired_command" != "$lock_target" ]; then
    _add_finding "V-BIN-WIRED-MISMATCH" "block" "$name" \
      "'${name}' wired command (${wired_command:-<empty>}) != locked target (${lock_target})." \
      "eidolons mcp install ${name}@${lock_version} --force"
  fi
}

# _verify_orphan_not_wired NAME LOCK_VERSION
# R6, asymmetric orphan handling for a LOCKED entry whose key is absent from
# .mcp.json (which is itself present + valid — the absent/invalid cases are
# handled by the caller before this is reached):
#   - other catalogue-known servers ARE wired  → V-PARTIALLY-WIRED (WARN):
#     partial-write signature, install activity clearly happened here.
#   - nothing else is wired either             → V-NOT-WIRED (INDETERMINATE,
#     --strict: BLOCK): indistinguishable from a committed-but-not-yet-
#     materialised .mcp.json (the fresh-clone shape R6 protects).
_verify_orphan_not_wired() {
  local name="$1" lock_version="$2"
  local sibling_found=false
  local wkey other_keys
  other_keys="$(jq -r --arg n "$name" '(.mcpServers // {}) | keys[] | select(. != $n)' "$MCP_JSON" 2>/dev/null || true)"
  while IFS= read -r wkey; do
    [ -z "$wkey" ] && continue
    if [ -n "$(mcp_catalogue_get "$wkey")" ]; then
      sibling_found=true
      break
    fi
  done <<< "$other_keys"

  if [ "$sibling_found" = "true" ]; then
    _add_finding "V-PARTIALLY-WIRED" "warn" "$name" \
      "'${name}' is locked but absent from .mcp.json, while other eidolons MCP servers ARE present (partial-write signature)." \
      "eidolons mcp install ${name}@${lock_version} --force"
  else
    local sev="indeterminate"
    [ "$STRICT" = "true" ] && sev="block"
    _add_finding "V-NOT-WIRED" "$sev" "$name" \
      "'${name}' is locked (version ${lock_version}) but not wired in .mcp.json." \
      "eidolons mcp install ${name}@${lock_version} --force"
  fi
}

_process_name() {
  local name="$1"
  local lock_entry
  lock_entry="$(printf '%s' "$LOCK_JSON" | jq --arg n "$name" '(.mcps // [])[] | select(.name == $n)')"

  if [ -z "$lock_entry" ]; then
    # R6 — wired-but-not-locked, catalogue-known servers only (a user's
    # hand-added MCP is ignored entirely, never mentioned — AC-8).
    if [ "$MCP_JSON_VALID" = "true" ]; then
      local wired_here
      wired_here="$(jq -r --arg n "$name" '(.mcpServers // {}) | has($n)' "$MCP_JSON")"
      if [ "$wired_here" = "true" ] && [ -n "$(mcp_catalogue_get "$name")" ]; then
        _add_finding "V-UNLOCKED-SERVER" "warn" "$name" \
          "'${name}' is wired in .mcp.json but has no eidolons.mcp.lock entry." \
          "eidolons mcp install ${name} to record it, or remove it from .mcp.json if it is not eidolons-managed."
      fi
    fi
    return 0
  fi

  local kind lock_version
  kind="$(printf '%s' "$lock_entry" | jq -r '.kind')"
  lock_version="$(printf '%s' "$lock_entry" | jq -r '.version')"

  case "$kind" in
    oci-image) _verify_oci_entry "$name" "$lock_entry" "$lock_version" ;;
    binary)    _verify_binary_entry "$name" "$lock_entry" "$lock_version" ;;
    *) : ;;
  esac
}

# ─── Build the name set to check ─────────────────────────────────────────────
if [ -n "$NAME_FILTER" ]; then
  NAMES_TO_CHECK="$NAME_FILTER"
else
  NAMES_TO_CHECK="$LOCK_NAMES"
  if [ "$MCP_JSON_VALID" = "true" ]; then
    _wired_names="$(jq -r '(.mcpServers // {}) | keys[]' "$MCP_JSON" 2>/dev/null || true)"
    while IFS= read -r _wn; do
      [ -z "$_wn" ] && continue
      if [ -n "$(mcp_catalogue_get "$_wn")" ] && ! _name_in_list "$_wn" "$LOCK_NAMES"; then
        NAMES_TO_CHECK="${NAMES_TO_CHECK}
${_wn}"
      fi
    done <<< "$_wired_names"
  fi
fi

while IFS= read -r _name; do
  [ -z "$_name" ] && continue
  _process_name "$_name"
done <<< "$NAMES_TO_CHECK"

# (--probe is rejected at argument-parse time — see the parser above. It must fail
# BEFORE any report is emitted, so that no caller can read a verdict which
# silently omitted the probe they asked for.)

# ─── Aggregate + emit ─────────────────────────────────────────────────────────
FINDINGS_ARR="$(printf '%s' "$FINDINGS_JSONL" | jq -s '[.[] | select(. != null)]')"
N_BLOCK="$(printf '%s' "$FINDINGS_ARR" | jq '[.[] | select(.severity == "block")] | length')"
N_WARN="$(printf '%s' "$FINDINGS_ARR" | jq '[.[] | select(.severity == "warn")] | length')"
N_INDET="$(printf '%s' "$FINDINGS_ARR" | jq '[.[] | select(.severity == "indeterminate")] | length')"

EXIT_CODE=0
if [ "$N_BLOCK" -gt 0 ]; then
  EXIT_CODE=1
elif [ "$N_INDET" -gt 0 ]; then
  EXIT_CODE=3
fi

if [ "$JSON" = "true" ]; then
  printf '%s' "$FINDINGS_ARR" | jq \
    --argjson bc "$N_BLOCK" --argjson wc "$N_WARN" --argjson ic "$N_INDET" --argjson ec "$EXIT_CODE" \
    '{findings: ., summary: {block: $bc, warn: $wc, indeterminate: $ic, exit_code: $ec}}'
else
  echo "eidolons mcp verify — wired reality (.mcp.json) vs locked intent (eidolons.mcp.lock)"
  echo ""
  _n_findings="$(printf '%s' "$FINDINGS_ARR" | jq 'length')"
  if [ "$_n_findings" -eq 0 ]; then
    echo "No findings."
  else
    printf '%s' "$FINDINGS_ARR" | jq -r '.[]
      | "[\(.severity | ascii_upcase)] \(.id) — \(.mcp): \(.message)"
        + (if .remedy then "\n  remedy: " + .remedy else "" end)'
  fi
  echo ""
  echo "Summary: ${N_BLOCK} block, ${N_WARN} warn, ${N_INDET} indeterminate."
  if [ "$N_INDET" -gt 0 ] && [ "$N_BLOCK" -eq 0 ]; then
    echo "INDETERMINATE"
  fi
fi

exit "$EXIT_CODE"
