#!/usr/bin/env bash
# cli/src/context.sh — 'eidolons context' sub-dispatcher (ECM P1 kernel).
#
# Routes to cli/src/context_<verb>.sh. Called by cli/eidolons after the
# 'context' token is peeled off the argument list.
#
# ECM governs the context economy of a running Eidolons session: how it
# measures its context, when it externalizes state to memory, and how a
# session hands off to its successor without a human noticing degradation.
# Opt-in, mechanical-gates-only, sidecar-on-disk, fail-open everywhere.
# See docs/specs/ecm/spec.md for the full contract.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<EOF
eidolons context — deterministic context-lifecycle kernel (ECM P1)

Usage: eidolons context <subcommand> [options]

Subcommands:
  status        Write .eidolons/.context/meter.json (D1 3-rung estimation ladder)
  policy        Evaluate roster/context-policy.yaml over the current meter
  externalize   Checkpoint identifiers to crystalium (file-floor when absent)
  handoff       Compose a session handoff brief + ECL envelope

Options:
  -h, --help    Show this help

Sidecar state (gitignored, opt-in, additive):
  .eidolons/.context/meter.json           latest context-utilization snapshot
  .eidolons/.context/policy-log.jsonl     every policy evaluation (audit trail)
  .eidolons/.context/budget-ledger.jsonl  append-only session budget accounting
  .eidolons/.context/handoff-*.md         session handoff briefs (+ .envelope.json)
  .eidolons/.context/externalized-*.json  file-floor manifests (crystalium absent)

Run 'eidolons context <subcommand> --help' for subcommand-specific help.
EOF
}

subcmd="${1:-}"
[ $# -gt 0 ] && shift

case "$subcmd" in
  status)      exec bash "$SELF_DIR/context_status.sh"      "$@" ;;
  policy)      exec bash "$SELF_DIR/context_policy.sh"      "$@" ;;
  externalize) exec bash "$SELF_DIR/context_externalize.sh" "$@" ;;
  handoff)     exec bash "$SELF_DIR/context_handoff.sh"     "$@" ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
  *)
    echo "Unknown context subcommand: $subcmd" >&2
    echo "" >&2
    echo "Available subcommands: status policy externalize handoff" >&2
    echo "Run 'eidolons context --help' for usage." >&2
    exit 2
    ;;
esac
