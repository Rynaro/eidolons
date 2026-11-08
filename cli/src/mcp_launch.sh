#!/usr/bin/env bash
# cli/src/mcp_launch.sh — session-scoped launcher for OCI MCP servers.
#
# Host configs (.mcp.json, .cursor/mcp.json, .codex/config.toml, opencode.json)
# wire every oci-image MCP as:
#
#   <nexus>/cli/src/mcp_launch.sh <mcp> [--keepalive shell|server] -- run <docker run argv...>
#
# Everything after `--` is the exact `docker run --rm -i ...` argv the nexus
# rendered from the catalogue template (resource flags, mounts, labels, pinned
# digest, serve command). Before this launcher existed, the host executed that
# argv directly, so every MCP client connection — every session, every Codex
# sub-agent thread, every reconnect — minted its own anonymous container with a
# random Docker name, each with its own resource ceiling.
#
# The launcher instead gives each HOST SESSION exactly one container per MCP:
#
#   1. Resolve the session anchor: walk the process-parent chain to the nearest
#      host-agent process (claude, codex, cursor, opencode, copilot, ...), then
#      keep walking to the TOPMOST ancestor of that same host kind. Nested
#      sessions (a `claude -p` sub-agent spawned by a parent claude, the codex
#      native binary under its node wrapper) therefore resolve to the parent
#      session. No host found → the direct MCP client process is the anchor
#      (one container per client, still named and bounded).
#   2. Name the container deterministically:
#        eidolons-<project>-<mcp>-<host>-<anchor pid>
#      and label it (eidolons.scope=session, eidolons.session=..., eidolons.mcp,
#      eidolons.spec=<argv hash>, eidolons.session.start=<anchor start hash>).
#   3. Under a per-container lock, reuse the container when it is running with
#      the same spec and anchor identity; otherwise (re)create it detached with
#      a keepalive PID 1 and the SAME flags, mounts, user and resource limits.
#   4. `exec docker exec -i <container> <entrypoint> <serve cmd>` — the MCP
#      stdio stream for this client is a process INSIDE the shared container,
#      so the cgroup ceiling bounds the whole session, however many sub-agents
#      connect.
#   5. One detached watcher per session removes the session's containers when
#      the anchor process exits. Each new session also sweeps containers whose
#      anchor is gone (crash, SIGKILL, reboot), and `eidolons mcp reap` applies
#      the same deterministic rule.
#
# Keepalive (catalogue runtime.keepalive):
#   shell  — `/bin/sh` sleep loop as PID 1 (images that ship a shell). The MCP
#            server only runs for connected clients; no idle background work.
#   server — the image's own serve command idles as PID 1 on an open, never
#            written stdin (distroless images with no shell). Cheap for small
#            stateless servers.
#
# Fail-open: any failure on the session path falls back to the legacy direct
# `docker run` argv, so an MCP never stops serving because of this launcher.
# Escape hatch: EIDOLONS_MCP_CONTAINER_SCOPE=client (env) forces the legacy
# path at runtime; `mcp_runtime.container_scope: client` in eidolons.yaml stops
# the nexus from rendering the launcher at all.
#
# STDOUT IS THE MCP JSON-RPC CHANNEL. Nothing but the final exec may write to
# it: fd 1 is parked on fd 3 and redirected to stderr for the whole script.
#
# Test seams (never set by hosts):
#   EIDOLONS_MCP_SESSION_PID / EIDOLONS_MCP_SESSION_HOST  — skip the walk.
#   EIDOLONS_MCP_WATCH_INTERVAL                            — watcher poll (s).
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile,
# no &>>. Depends only on bash, ps, cksum, mkdir and the docker CLI (no jq/yq:
# GUI hosts may launch this with a minimal PATH).
# ═══════════════════════════════════════════════════════════════════════════

set -u

exec 3>&1 1>&2

_launch_log() { printf 'eidolons-mcp: %s\n' "$*" >&2; }

if [ $# -lt 1 ]; then
  _launch_log "usage: mcp_launch.sh <mcp> [--keepalive shell|server] -- run <docker argv...>"
  exit 2
fi

MCP_NAME="$1"
shift
KEEPALIVE="server"
while [ $# -gt 0 ]; do
  case "$1" in
    --keepalive) KEEPALIVE="${2:-server}"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# _launch_direct — legacy behaviour: run the rendered argv verbatim.
_launch_direct() {
  exec docker "$@" 1>&3 3>&-
}

case "${EIDOLONS_MCP_CONTAINER_SCOPE:-session}" in
  client) _launch_direct "$@" ;;
esac
[ "${1:-}" = "run" ] || _launch_direct "$@"
command -v docker >/dev/null 2>&1 || _launch_direct "$@"

# ─── Split the docker run argv: flags | image | command ─────────────────────
# The image is the digest-pinned reference (every catalogue template pins one).
# Per-connection flags (--rm, -i, -t, -d, --name) are dropped: the session
# container is long-lived and named by the launcher.
FLAGS=()
CMD=()
IMAGE=""
SLUG=""
_skip=0
_prev=""
for _a in "${@:2}"; do
  if [ -n "$IMAGE" ]; then
    CMD+=("$_a")
    continue
  fi
  if [ "$_skip" -eq 1 ]; then
    _skip=0
    continue
  fi
  case "$_a" in
    --rm|-i|-t|-it|-ti|-d|--interactive|--tty|--detach) ;;
    --name) _skip=1 ;;
    --name=*) ;;
    *@sha256:*)
      if [ "$_prev" = "--label" ] || [ "$_prev" = "-e" ] || [ "$_prev" = "-v" ]; then
        FLAGS+=("$_a")
      else
        IMAGE="$_a"
      fi
      ;;
    *)
      FLAGS+=("$_a")
      case "$_a" in
        eidolons.project=*) [ "$_prev" = "--label" ] && SLUG="${_a#eidolons.project=}" ;;
      esac
      ;;
  esac
  _prev="$_a"
done

[ -n "$IMAGE" ] || _launch_direct "$@"

if [ -z "$SLUG" ]; then
  SLUG="$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's|^-||' -e 's|-$||')"
  FLAGS+=(--label "eidolons.project=${SLUG}")
fi

# ─── Session anchor ─────────────────────────────────────────────────────────

# _launch_host_kind COMMAND — host-agent kind for a process command line, or
# empty. Node/bun wrappers are classified by their script path.
_launch_host_kind() {
  local cmd="$1" first rest base
  case "$cmd" in
    *"/Cursor.app/"*|*"Cursor Helper"*) printf 'cursor'; return 0 ;;
    *"/Visual Studio Code.app/"*|*"Code Helper"*) printf 'vscode'; return 0 ;;
  esac
  first="${cmd%% *}"
  if [ -n "${CLAUDE_CODE_EXECPATH:-}" ] && [ "$first" = "$CLAUDE_CODE_EXECPATH" ]; then
    printf 'claude'
    return 0
  fi
  base="${first##*/}"
  case "$base" in
    node|bun|deno)
      rest="${cmd#"$first"}"
      rest="${rest# }"
      first="${rest%% *}"
      base="${first##*/}"
      ;;
  esac
  case "$base" in
    claude|claude-code) printf 'claude' ;;
    codex|codex-*|codex.js) printf 'codex' ;;
    cursor|cursor-agent) printf 'cursor' ;;
    opencode) printf 'opencode' ;;
    copilot) printf 'copilot' ;;
    gemini) printf 'gemini' ;;
    cli.js|cli.mjs)
      case "$first" in
        *claude-code*) printf 'claude' ;;
        *codex*) printf 'codex' ;;
      esac
      ;;
  esac
  return 0
}

# _launch_start_id PID — stable identity of a process start (PID-reuse guard).
_launch_start_id() {
  ps -o lstart= -p "$1" 2>/dev/null | cksum | awk '{print $1}'
}

ANCHOR_PID=""
HOST_KIND=""
if [ -n "${EIDOLONS_MCP_SESSION_PID:-}" ]; then
  ANCHOR_PID="$EIDOLONS_MCP_SESSION_PID"
  HOST_KIND="${EIDOLONS_MCP_SESSION_HOST:-session}"
else
  _pid="$PPID"
  _hops=0
  while [ "$_hops" -lt 40 ] && [ -n "$_pid" ] && [ "$_pid" -gt 1 ] 2>/dev/null; do
    _row="$(ps -o ppid=,command= -p "$_pid" 2>/dev/null)" || break
    [ -n "$_row" ] || break
    _row="${_row#"${_row%%[! ]*}"}"
    _ppid="${_row%% *}"
    _cmd="${_row#"$_ppid"}"
    _cmd="${_cmd#"${_cmd%%[! ]*}"}"
    _kind="$(_launch_host_kind "$_cmd")"
    if [ -n "$_kind" ]; then
      if [ -z "$HOST_KIND" ]; then
        HOST_KIND="$_kind"
        ANCHOR_PID="$_pid"
      elif [ "$_kind" = "$HOST_KIND" ]; then
        ANCHOR_PID="$_pid"
      fi
    fi
    _pid="$_ppid"
    _hops=$((_hops + 1))
  done
  if [ -z "$ANCHOR_PID" ]; then
    ANCHOR_PID="$PPID"
    HOST_KIND="client"
  fi
fi

case "$ANCHOR_PID" in
  ''|*[!0-9]*) _launch_direct "$@" ;;
esac

ANCHOR_START="$(_launch_start_id "$ANCHOR_PID")"
HOST_ID="$(hostname 2>/dev/null || uname -n)"
SESSION_KEY="${HOST_KIND}-${ANCHOR_PID}-${ANCHOR_START}"
CNAME="eidolons-${SLUG}-${MCP_NAME}-${HOST_KIND}-${ANCHOR_PID}"
SPEC="$(printf '%s\n' "$KEEPALIVE" "$IMAGE" ${FLAGS[@]+"${FLAGS[@]}"} -- ${CMD[@]+"${CMD[@]}"} | cksum | awk '{print $1}')"

RUN_DIR="${EIDOLONS_HOME:-$HOME/.eidolons}/run/mcp"
mkdir -p "$RUN_DIR" 2>/dev/null || _launch_direct "$@"

# ─── Locking (mkdir is atomic on every POSIX filesystem) ────────────────────

_launch_lock() {
  local dir="$1" tries=0 holder
  while ! mkdir "$dir" 2>/dev/null; do
    holder="$(cat "$dir/pid" 2>/dev/null || true)"
    if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
      rm -rf "$dir"
      continue
    fi
    tries=$((tries + 1))
    if [ "$tries" -ge 1800 ]; then
      # 180s: a first-time image pull can legitimately hold the lock this
      # long. Past that the holder is wedged; break the lock once.
      rm -rf "$dir"
      mkdir "$dir" 2>/dev/null || return 1
      break
    fi
    sleep 0.1
  done
  printf '%s\n' "$$" > "$dir/pid"
  return 0
}

_launch_unlock() { rm -rf "$1"; }

# ─── Session cleanup ────────────────────────────────────────────────────────

# _launch_sweep — remove session containers on this host whose anchor process
# is gone. Runs once per new session (when its watcher is spawned).
_launch_sweep() {
  local rows name pid start host
  rows="$(docker ps -a --filter "label=eidolons.scope=session" \
    --format '{{.Names}}	{{.Label "eidolons.session.pid"}}	{{.Label "eidolons.session.start"}}	{{.Label "eidolons.session.host_id"}}' 2>/dev/null || true)"
  [ -n "$rows" ] || return 0
  while IFS='	' read -r name pid start host; do
    [ -n "$name" ] || continue
    [ "$host" = "$HOST_ID" ] || continue
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    if kill -0 "$pid" 2>/dev/null && [ "$(_launch_start_id "$pid")" = "$start" ]; then
      continue
    fi
    docker rm -f "$name" >/dev/null 2>&1 || true
  done <<EOF
$rows
EOF
}

# _launch_detach CMD... — run CMD in a new session so a host that signals the
# MCP client's process group on shutdown does not take the watcher with it.
# Every inherited stdio fd is closed — fd 3 in particular is the parked MCP
# stdout pipe: a watcher holding it would keep the host from ever seeing EOF
# on the server's stdout after the client exits.
_launch_detach() {
  if command -v setsid >/dev/null 2>&1; then
    nohup setsid "$@" </dev/null >/dev/null 2>&1 3>&- &
  elif command -v perl >/dev/null 2>&1; then
    nohup perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' "$@" </dev/null >/dev/null 2>&1 3>&- &
  else
    nohup "$@" </dev/null >/dev/null 2>&1 3>&- &
  fi
}

# _launch_ensure_watcher — exactly one watcher per session removes every
# container labeled with this session once the anchor process exits.
_launch_ensure_watcher() {
  local wdir="$RUN_DIR/watch-${SESSION_KEY}" wpid
  if ! mkdir "$wdir" 2>/dev/null; then
    wpid="$(cat "$wdir/pid" 2>/dev/null || true)"
    if [ -z "$wpid" ] || kill -0 "$wpid" 2>/dev/null; then
      return 0
    fi
    rm -rf "$wdir"
    mkdir "$wdir" 2>/dev/null || return 0
  fi
  _launch_sweep
  # shellcheck disable=SC2016
  _launch_detach bash -c '
    pid="$1"; start="$2"; key="$3"; interval="$4"; wdir="$5"
    while kill -0 "$pid" 2>/dev/null \
      && [ "$(ps -o lstart= -p "$pid" 2>/dev/null | cksum | awk "{print \$1}")" = "$start" ]; do
      sleep "$interval"
    done
    ids="$(docker ps -aq --filter "label=eidolons.session=$key" 2>/dev/null)"
    [ -n "$ids" ] && docker rm -f $ids >/dev/null 2>&1
    rm -rf "$wdir"
  ' eidolons-mcp-watch "$ANCHOR_PID" "$ANCHOR_START" "$SESSION_KEY" \
    "${EIDOLONS_MCP_WATCH_INTERVAL:-5}" "$wdir"
  printf '%s\n' "$!" > "$wdir/pid"
}

# ─── Ensure the session container ───────────────────────────────────────────

LOCK_DIR="$RUN_DIR/${CNAME}.lock"
_launch_lock "$LOCK_DIR" || _launch_direct "$@"

_state="$(docker inspect -f '{{.State.Running}} {{index .Config.Labels "eidolons.spec"}} {{index .Config.Labels "eidolons.session.start"}}' "$CNAME" 2>/dev/null || true)"
if [ "$_state" != "true ${SPEC} ${ANCHOR_START}" ]; then
  if [ -n "$_state" ]; then
    # Stale: anchor PID reused, spec changed (upgrade / new limits), or the
    # container stopped. Replace it under the lock.
    docker rm -f "$CNAME" >/dev/null 2>&1 || true
  fi
  LABELS=(
    --label "eidolons.scope=session"
    --label "eidolons.mcp=${MCP_NAME}"
    --label "eidolons.session=${SESSION_KEY}"
    --label "eidolons.session.host=${HOST_KIND}"
    --label "eidolons.session.pid=${ANCHOR_PID}"
    --label "eidolons.session.start=${ANCHOR_START}"
    --label "eidolons.session.host_id=${HOST_ID}"
    --label "eidolons.spec=${SPEC}"
  )
  if [ "$KEEPALIVE" = "shell" ]; then
    _created="$(docker run -d -i --name "$CNAME" "${LABELS[@]}" ${FLAGS[@]+"${FLAGS[@]}"} \
      --entrypoint /bin/sh "$IMAGE" \
      -c 'trap "exit 0" TERM INT HUP; while :; do sleep 86400 & wait $!; done' 2>&1)"
  else
    _created="$(docker run -d -i --name "$CNAME" "${LABELS[@]}" ${FLAGS[@]+"${FLAGS[@]}"} \
      "$IMAGE" ${CMD[@]+"${CMD[@]}"} 2>&1)"
  fi
  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    _launch_unlock "$LOCK_DIR"
    _launch_log "${MCP_NAME}: session container create failed; falling back to a per-client container"
    _launch_log "$(printf '%s' "$_created" | tail -1)"
    docker rm -f "$CNAME" >/dev/null 2>&1 || true
    _launch_direct "$@"
  fi
fi

_launch_ensure_watcher
_launch_unlock "$LOCK_DIR"

# ─── Attach this client to the session container ────────────────────────────
# docker exec does not apply the image ENTRYPOINT; prepend it explicitly. The
# exec inherits the container's user, working dir and environment.
EXEC_ARGV=()
while IFS= read -r _line; do
  [ -n "$_line" ] && EXEC_ARGV+=("$_line")
done <<EOF
$(docker image inspect -f '{{range .Config.Entrypoint}}{{println .}}{{end}}' "$IMAGE" 2>/dev/null)
EOF
if [ "${#CMD[@]}" -gt 0 ]; then
  EXEC_ARGV+=("${CMD[@]}")
else
  while IFS= read -r _line; do
    [ -n "$_line" ] && EXEC_ARGV+=("$_line")
  done <<EOF
$(docker image inspect -f '{{range .Config.Cmd}}{{println .}}{{end}}' "$IMAGE" 2>/dev/null)
EOF
fi
[ "${#EXEC_ARGV[@]}" -gt 0 ] || _launch_direct "$@"

exec docker exec -i "$CNAME" "${EXEC_ARGV[@]}" 1>&3 3>&-
