#!/usr/bin/env bash
# cli/src/mcp_assess.sh — record an MCP's ESL escalation decision into the lock.
#
# Usage: eidolons mcp assess <name> [--project-root PATH]
#
# RECORD hop of the ESL escalation auto-flip (FORGE verdict H5). Runs the MCP's
# `assess` op against the consumer project (for tonberry: `tonberry assess`),
# reads back {signals, thresholds, tripped[], recommended_mode}, and the NEXUS
# (this script — never the MCP) upserts the recorded enforcement mode plus its
# producing signals into the MCP's eidolons.mcp.lock entry. The HONOR hop lives
# in the cortex (methodology/cortex/esl-protocol.md): a verifying caller reads
# `enforcement` from the lock and passes `--mode block` when it reads "block".
#
# Graceful skip (ESL is opt-in): if the MCP is not installed or its assess op is
# unavailable, this warns and no-ops with exit 0 — it never hard-fails a project.
# Non-zero exit is reserved for usage errors. An "advisory" result is a normal
# exit 0, not a failure.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

usage() {
  cat <<EOF
eidolons mcp assess — record an MCP's ESL escalation decision into the lock

Usage: eidolons mcp assess <name> [--project-root PATH]

Runs the MCP's 'assess' op against the project and records the resulting
enforcement mode (advisory|block) plus its producing signals into the MCP's
eidolons.mcp.lock entry. The nexus owns the lock-write; the MCP only computes.

Arguments:
  name                 MCP name exposing an 'assess' op (e.g. tonberry).

Options:
  --project-root PATH  Project directory to assess (default: cwd).
  -h, --help           Show this help.

Examples:
  eidolons mcp assess tonberry
  eidolons mcp assess tonberry --project-root /path/to/project

Graceful skip: if the MCP is not installed or its assess op is unavailable,
this warns and exits 0 (ESL is opt-in — never hard-fails the project).
EOF
}

if [ $# -eq 0 ]; then
  usage >&2
  exit 2
fi

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

name="${1:-}"
shift

project_root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      [ -z "${2:-}" ] && die "--project-root requires an argument"
      project_root="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    -*) warn "Unknown option: $1"; usage >&2; exit 2 ;;
    *)  warn "Unexpected argument: $1"; usage >&2; exit 2 ;;
  esac
done

project_root="${project_root:-$(pwd)}"
project_root="$(cd "$project_root" 2>/dev/null && pwd)" \
  || die "project root does not exist: ${project_root}"

# Validate the MCP exists in the catalogue (usage error if not).
kind="$(mcp_resolve_kind "$name")"

# ── Graceful skip: MCP must be installed (lock entry present). ────────────────
# [G-DEGRADE] Mirrors the 'mcp health' zero-wire warning: ESL is opt-in, so an
# absent MCP is a no-op (exit 0), not a failure.
lock_entry="$(mcp_lock_entry "$name")"
if [ -z "$lock_entry" ]; then
  warn "${name} is not installed in this project — skipping ESL assessment (no-op)."
  warn "Install it first: eidolons mcp install ${name}"
  exit 0
fi

# Only oci-image MCPs expose an 'assess' op in the current contract.
if [ "$kind" != "oci-image" ]; then
  warn "${name} (kind=${kind}) does not expose an 'assess' op — skipping ESL assessment (no-op)."
  exit 0
fi

say "Assessing ${name} over ${project_root}"

# ── Run the MCP's assess op (the MCP computes; the nexus records). ────────────
assess_json=""
assess_rc=0
assess_json="$(mcp_driver_oci_image_assess "$name" "$project_root")" || assess_rc=$?

if [ "$assess_rc" -ne 0 ] || [ -z "$assess_json" ]; then
  warn "${name}: assess op unavailable — skipping ESL assessment (no-op)."
  exit 0
fi

# Validate the assess output is JSON; if not, degrade gracefully.
if ! printf '%s' "$assess_json" | jq empty >/dev/null 2>&1; then
  warn "${name}: assess produced non-JSON output — skipping ESL assessment (no-op)."
  exit 0
fi

# ── Parse {signals, thresholds, tripped[], recommended_mode}. ─────────────────
recommended_mode="$(printf '%s' "$assess_json" \
  | jq -r '.recommended_mode // empty')"
signals_json="$(printf '%s' "$assess_json" | jq -c '.signals // {}')"
thresholds_json="$(printf '%s' "$assess_json" | jq -c '.thresholds // {}')"
tripped_json="$(printf '%s' "$assess_json" | jq -c '.tripped // []')"

# Normalize/guard recommended_mode to the closed set {advisory,block}.
case "$recommended_mode" in
  block)    enforcement="block" ;;
  advisory) enforcement="advisory" ;;
  *)
    # Unknown / absent recommendation → default to advisory (safe, opt-in posture).
    warn "${name}: assess returned no recognized recommended_mode ('${recommended_mode:-<empty>}') — defaulting to advisory."
    enforcement="advisory"
    ;;
esac

assessed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ── RECORD (nexus owns the lock-write — C-OWNER). ─────────────────────────────
# Direct read-modify-write that bypasses mcp_lock_upsert's no-op signature (which
# excludes enforcement* — see mcp_lock_set_enforcement).
if mcp_lock_set_enforcement "$name" "$enforcement" "$signals_json" "$thresholds_json" "$assessed_at"; then
  ok "${name} enforcement recorded: ${enforcement}"
else
  warn "${name}: could not record enforcement (no lock entry) — no-op."
  exit 0
fi

# ── Machine-readable result to stdout (logs went to stderr). ──────────────────
jq -n \
  --arg name "$name" \
  --arg enforcement "$enforcement" \
  --arg recommended_mode "${recommended_mode:-advisory}" \
  --argjson tripped "$tripped_json" \
  --arg assessed_at "$assessed_at" \
  '{
    name: $name,
    enforcement: $enforcement,
    recommended_mode: $recommended_mode,
    tripped: $tripped,
    assessed_at: $assessed_at
  }'
