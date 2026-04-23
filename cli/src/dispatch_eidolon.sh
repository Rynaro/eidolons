#!/usr/bin/env bash
# eidolons dispatch — generic per-Eidolon subcommand router.
#
# Usage: eidolons <eidolon> <subcommand> [args...]
#
# Looks up a bash script at .eidolons/<eidolon>/commands/<subcommand>.sh
# (installed target first, nexus cache as fallback) and execs it with cwd
# set to the consumer project root — matches sync/doctor convention.
#
# Eidolons declare their subcommands by shipping commands/*.sh files in
# their source repo. The per-Eidolon install.sh copies commands/*.sh
# into the installed target, which this dispatcher discovers at runtime.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  local eidolon="${1:-<eidolon>}"
  cat <<EOF
eidolons ${eidolon} <subcommand> [args...]

Run a per-Eidolon subcommand shipped by ${eidolon}'s install.

Subcommands are discovered from:
  .eidolons/${eidolon}/commands/*.sh       (installed target — preferred)
  ~/.eidolons/cache/${eidolon}@VER/commands/*.sh   (cache fallback)

Common forms:
  eidolons ${eidolon} --help               List available subcommands
  eidolons ${eidolon} <sub>                Execute the subcommand
  eidolons ${eidolon} <sub> [args]         Execute with args passed through
EOF
}

EIDOLON="${1:-}"
[[ -z "$EIDOLON" ]] && { echo "Error: eidolon name required" >&2; usage; exit 2; }
shift

# Validate the Eidolon exists in the roster before we go any further.
roster_get "$EIDOLON" >/dev/null

# ─── Resolve the commands/ directory ──────────────────────────────────────
# Prefer the installed target in the user's project (cwd-relative). Fall
# back to the nexus cache if the Eidolon isn't installed here yet.
INSTALLED_COMMANDS=""
if [[ -d "./.eidolons/${EIDOLON}/commands" ]]; then
  INSTALLED_COMMANDS="./.eidolons/${EIDOLON}/commands"
fi

CACHED_COMMANDS=""
# Look up the roster version to find the cache. Don't fail here if cache
# is missing — only error if no source of commands is found.
version="$(roster_get "$EIDOLON" | jq -r '.versions.latest // empty')"
if [[ -z "$INSTALLED_COMMANDS" && -n "$version" ]]; then
  _candidate="$CACHE_DIR/${EIDOLON}@${version}/commands"
  [[ -d "$_candidate" ]] && CACHED_COMMANDS="$_candidate"
fi

COMMANDS_DIR="${INSTALLED_COMMANDS:-${CACHED_COMMANDS}}"

# ─── Help: list discovered subcommands ────────────────────────────────────
SUB="${1:-}"
if [[ -z "$SUB" || "$SUB" == "-h" || "$SUB" == "--help" ]]; then
  usage "$EIDOLON"
  if [[ -n "$COMMANDS_DIR" ]]; then
    echo ""
    echo "${BOLD}Available subcommands for ${EIDOLON}${RESET} (from ${COMMANDS_DIR}):"
    _found=false
    for _s in "$COMMANDS_DIR"/*.sh; do
      [[ -f "$_s" ]] || continue
      printf "  %s\n" "$(basename "${_s%.sh}")"
      _found=true
    done
    if [[ "$_found" != "true" ]]; then
      echo "  (none — ${EIDOLON} does not ship any subcommands in this install)"
    fi
  else
    echo ""
    echo "${BOLD}${EIDOLON}${RESET} is declared in the roster but not installed or cached."
    echo "Run 'eidolons sync' (with ${EIDOLON} in eidolons.yaml) to install."
  fi
  exit 0
fi

shift  # drop the subcommand name from $@

# ─── Resolve and exec the subcommand script ───────────────────────────────
if [[ -z "$COMMANDS_DIR" ]]; then
  die "${EIDOLON} has no commands/ directory — not installed in this project, and no cached clone at ${version:-<unknown version>}."
fi

SUB_SCRIPT="${COMMANDS_DIR}/${SUB}.sh"
if [[ ! -f "$SUB_SCRIPT" ]]; then
  echo "Error: no subcommand '${SUB}' for ${EIDOLON}." >&2
  echo "  Looked at: ${SUB_SCRIPT}" >&2
  echo "  Run 'eidolons ${EIDOLON} --help' to list available subcommands." >&2
  exit 2
fi

if [[ ! -x "$SUB_SCRIPT" ]]; then
  # Non-executable files are still runnable via bash — just warn.
  info "${SUB_SCRIPT} is not executable; invoking via bash"
fi

exec bash "$SUB_SCRIPT" "$@"
