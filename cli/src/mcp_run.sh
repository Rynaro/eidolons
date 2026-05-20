#!/usr/bin/env bash
# cli/src/mcp_run.sh — pass-through to a runnable MCP binary.
#
# Usage: eidolons mcp run <name> [<args>...]
#
# In v1.3, only kind=binary MCPs that declare a runnable entrypoint participate.
# junction is the only such MCP. A generalised 'mcp run' for kind=oci-image
# (docker run pass-through) is a future spec.
#
# Looks up junction's binary path from eidolons.mcp.lock (preferred) or
# $EIDOLONS_HOME/cache/junction@*/junction (fallback) and exec's it with all
# remaining args.
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
eidolons mcp run — pass-through to a runnable MCP binary

Usage: eidolons mcp run <name> [<args>...]

Arguments:
  name    MCP name. In v1.3, only 'junction' is supported.
  args    Arguments forwarded verbatim to the MCP binary.

Examples:
  eidolons mcp run junction verify --plan plan.json
  eidolons mcp run junction --version

Note: This command is junction-only in v1.3. The generalised form for
kind=oci-image MCPs is a future spec.
EOF
}

if [ $# -eq 0 ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

mcp_name="$1"
shift

case "$mcp_name" in
  junction)
    # Locate binary: prefer lockfile target, then cache glob.
    bin=""
    lock_target="$(mcp_lock_entry "junction" | jq -r '.target // ""')"
    if [ -n "$lock_target" ] && [ -x "$lock_target" ]; then
      bin="$lock_target"
    else
      # Fallback: scan cache.
      d=""
      for d in "${CACHE_DIR}/junction@"*/; do
        if [ -d "$d" ]; then
          if [ -x "${d%/}/junction" ]; then
            bin="${d%/}/junction"
            break
          elif [ -x "${d%/}/bin/junction" ]; then
            bin="${d%/}/bin/junction"
            break
          fi
        fi
      done
    fi

    if [ -z "$bin" ]; then
      die "Junction is not installed. Run: eidolons mcp install junction"
    fi

    exec "$bin" "$@"
    ;;
  *)
    die "eidolons mcp run: '$mcp_name' is not a runnable MCP in v1.3 (only 'junction' is supported)"
    ;;
esac
