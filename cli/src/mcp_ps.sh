#!/usr/bin/env bash
# cli/src/mcp_ps.sh — list Eidolons MCP containers grouped by owning session.
#
# Usage: eidolons mcp ps [--all] [--project <slug>] [--json] [-h|--help]
#
# Session-scoped containers (minted by cli/src/mcp_launch.sh) are labelled with
# their owning host session (eidolons.session.host + .pid). This view answers
# "which session started which container, is that session still alive, and
# what is it using". Legacy per-client containers (eidolons.project label but
# no eidolons.scope) are counted separately — `eidolons mcp reap` cleans them.
#
# Exit codes: 0 always (docker absent → empty listing); 2 usage error.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile,
# no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<EOF
eidolons mcp ps — list MCP containers grouped by owning host session

Usage: eidolons mcp ps [options]

Options:
  --all              Every project (default: the current project only)
  --project <slug>   Restrict to containers labelled eidolons.project=<slug>
  --json             Machine-readable output (schema eidolons/mcp-ps.v1)
  -h, --help         Show this help

Each host session (a Claude Code, Codex, Cursor, ... main session) owns one
container per MCP, named eidolons-<project>-<mcp>-<host>-<pid>; its sub-agents
attach to that container instead of starting their own. SESSION shows the
owning host process; STATE is "live" while it runs and "dead" once it is gone
(dead sessions are removed automatically, or by 'eidolons mcp reap --yes').
EOF
}

ALL=false
PROJECT=""
JSON=false
while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=true; shift ;;
    --project)
      [ -n "${2:-}" ] || { echo "--project requires an argument" >&2; exit 2; }
      PROJECT="$2"; shift 2 ;;
    --json) JSON=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
if [ "$ALL" = "true" ] && [ -n "$PROJECT" ]; then
  echo "--all is mutually exclusive with --project" >&2
  exit 2
fi
[ "$ALL" = "true" ] || PROJECT="${PROJECT:-$(project_slug)}"

ME="${EIDOLONS_PS_HOST_ID:-$(hostname 2>/dev/null || uname -n)}"

# _ps_state PID START HOST_ID — live | dead | foreign (see mcp_reap.sh).
_ps_state() {
  local pid="$1" start="$2" host="$3"
  if [ -n "$host" ] && [ "$host" != "$ME" ]; then printf 'foreign'; return 0; fi
  case "$pid" in ''|*[!0-9]*) printf 'dead'; return 0 ;; esac
  if kill -0 "$pid" 2>/dev/null \
     && [ "$(ps -o lstart= -p "$pid" 2>/dev/null | cksum | awk '{print $1}')" = "$start" ]; then
    printf 'live'
  else
    printf 'dead'
  fi
}

ROWS=""
LEGACY=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  filters=(--filter "label=eidolons.scope=session")
  legacy_filter="label=eidolons.project"
  if [ -n "$PROJECT" ]; then
    filters+=(--filter "label=eidolons.project=${PROJECT}")
    legacy_filter="label=eidolons.project=${PROJECT}"
  fi
  fmt='{{.Names}}	{{.Label "eidolons.project"}}	{{.Label "eidolons.mcp"}}	{{.Label "eidolons.session.host"}}	{{.Label "eidolons.session.pid"}}	{{.Label "eidolons.session.start"}}	{{.Label "eidolons.session.host_id"}}	{{.RunningFor}}'
  RAW="$(docker ps "${filters[@]}" --format "$fmt" 2>/dev/null || true)"
  LEGACY="$(docker ps --filter "$legacy_filter" --format '{{.Label "eidolons.scope"}}' 2>/dev/null \
    | awk 'length($0)==0{c++} END{print c+0}')"

  names=""
  while IFS='	' read -r n _rest; do
    [ -n "$n" ] && names="${names} ${n}"
  done <<< "$RAW"
  STATS=""
  if [ -n "$names" ]; then
    # shellcheck disable=SC2086
    STATS="$(docker stats --no-stream --format '{{.Name}}	{{.MemUsage}}	{{.CPUPerc}}	{{.PIDs}}' $names 2>/dev/null || true)"
  fi

  while IFS='	' read -r n proj mcp host pid start hid age; do
    [ -n "$n" ] || continue
    state="$(_ps_state "$pid" "$start" "$hid")"
    srow="$(printf '%s\n' "$STATS" | awk -F'\t' -v n="$n" '$1 == n {print $2"\t"$3"\t"$4; exit}')"
    mem="${srow%%	*}"; rest="${srow#*	}"; cpu="${rest%%	*}"; pids="${rest#*	}"
    [ -n "$srow" ] || { mem="-"; cpu="-"; pids="-"; }
    ROWS="${ROWS}${host}-${pid}	${state}	${proj}	${mcp}	${n}	${mem}	${cpu}	${pids}	${age}
"
  done <<< "$RAW"
  ROWS="$(printf '%s' "$ROWS" | sort -t'	' -k1,1 -k4,4)"
fi

if [ "$JSON" = "true" ]; then
  printf '%s\n' "$ROWS" | jq -R -s --arg project "${PROJECT:-*}" --argjson legacy "${LEGACY:-0}" '
    [split("\n")[] | select(length > 0) | split("\t")
      | {session:.[0], state:.[1], project:.[2], mcp:.[3], container:.[4],
         memory:.[5], cpu:.[6], pids:.[7], running_for:.[8]}] as $c
    | {schema:"eidolons/mcp-ps.v1", project:$project, containers:$c,
       legacy_per_client_containers:$legacy}'
  exit 0
fi

if [ -z "$ROWS" ]; then
  echo "No session-scoped MCP containers${PROJECT:+ for project '${PROJECT}'}."
else
  {
    printf 'SESSION\tSTATE\tPROJECT\tMCP\tCONTAINER\tMEM USAGE / LIMIT\tCPU\tPIDS\tUP\n'
    printf '%s\n' "$ROWS"
  } | awk -F'\t' '
    { for (i = 1; i <= NF; i++) { cell[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } n = NF; rows = NR }
    END { for (r = 1; r <= rows; r++) { line = ""; for (i = 1; i <= n; i++) line = line sprintf("%-" w[i] + 2 "s", cell[r, i]); sub(/ +$/, "", line); print line } }'
fi
if [ "${LEGACY:-0}" -gt 0 ]; then
  echo ""
  echo "${LEGACY} legacy per-client MCP container(s) running (pre-session wiring)."
  echo "Re-render with 'eidolons mcp sync --repair-wiring', then clean up with 'eidolons mcp reap'."
fi
exit 0
