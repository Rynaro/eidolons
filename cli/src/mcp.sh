#!/usr/bin/env bash
# cli/src/mcp.sh — MCP store sub-dispatcher for 'eidolons mcp <verb>'.
#
# Routes to cli/src/mcp_<verb>.sh.  Called by cli/eidolons after stripping the
# leading 'mcp' token from the argument list.
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
eidolons mcp — unified MCP server store

Usage: eidolons mcp <subcommand> [options]

Subcommands:
  list                    List catalogue MCPs with install / health status
  show <name>             Show details for a specific MCP
  install <name>[@<ver>]  Install an MCP (idempotent)
  refresh <name>          Re-fetch an MCP artefact (image pull / binary re-download)
  uninstall <name>        Remove an MCP from this project
  upgrade [<name>[@<ver>]|--all]  Upgrade installed MCPs (pins.stable, or explicit version)
  use <name>@<ver>        Switch to any catalogue-published version (up or down)
  assess <name>           Record an MCP's ESL escalation decision into the lock
  sync                    Reconcile project eidolons.yaml mcps: block with installed state
  health [<name>|--all]   Run health probes for installed MCPs
  run <name> [<args>...]  Pass-through to a runnable MCP (binary kind only in v1.3)
  pull <name>             Pull an oci-image MCP image onto this host (catalogue-pin driven)
  images                  Show image inventory for oci-image MCPs (present/digest/drift)

Options:
  -h, --help    Show this help

Environment:
  EIDOLONS_SUPPRESS_DEPRECATED=1   Suppress DEPRECATED lines from legacy verbs

Run 'eidolons mcp <subcommand> --help' for subcommand-specific help.
EOF
}

subcmd="${1:-}"
[ $# -gt 0 ] && shift

case "$subcmd" in
  list)      exec bash "$SELF_DIR/mcp_list.sh"      "$@" ;;
  show)      exec bash "$SELF_DIR/mcp_show.sh"      "$@" ;;
  install)   exec bash "$SELF_DIR/mcp_install.sh"   "$@" ;;
  refresh)   exec bash "$SELF_DIR/mcp_refresh.sh"   "$@" ;;
  uninstall) exec bash "$SELF_DIR/mcp_uninstall.sh" "$@" ;;
  upgrade)   exec bash "$SELF_DIR/mcp_upgrade.sh"   "$@" ;;
  use)       exec bash "$SELF_DIR/mcp_use.sh"       "$@" ;;
  assess)    exec bash "$SELF_DIR/mcp_assess.sh"    "$@" ;;
  sync)      exec bash "$SELF_DIR/mcp_sync.sh"      "$@" ;;
  health)    exec bash "$SELF_DIR/mcp_health.sh"    "$@" ;;
  run)       exec bash "$SELF_DIR/mcp_run.sh"       "$@" ;;
  pull)      exec bash "$SELF_DIR/mcp_pull.sh"      "$@" ;;
  images)    exec bash "$SELF_DIR/mcp_images.sh"    "$@" ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
  *)
    echo "Unknown mcp subcommand: $subcmd" >&2
    echo "" >&2
    echo "Available subcommands: list show install refresh uninstall upgrade use assess sync health run pull images" >&2
    echo "Run 'eidolons mcp --help' for usage." >&2
    exit 2
    ;;
esac
