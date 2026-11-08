#!/usr/bin/env bats
#
# cli/tests/mcp_launch.bats — session-scoped OCI MCP launcher (cli/src/mcp_launch.sh).
#
# A stateful fake docker records every invocation in docker.log and keeps one
# state dir per "created" container so inspect/reuse behave like the daemon:
#   run -d ...      → stores labels, prints a container id on STDOUT (must not
#                     leak into the MCP stream)
#   run (no -d)     → prints DIRECT-RUN on stdout (legacy per-client path)
#   inspect NAME    → "true <spec> <start>" when created, rc 1 otherwise
#   image inspect   → entrypoint / cmd lines from FAKE_ENTRYPOINT / FAKE_CMD
#   exec ...        → prints EXEC-STDOUT on stdout
#   rm -f NAME      → forgets the container
#
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no readarray.

load helpers

LAUNCH="$EIDOLONS_ROOT/cli/src/mcp_launch.sh"
TON_IMAGE="ghcr.io/rynaro/tonberry@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
CRY_IMAGE="ghcr.io/rynaro/crystalium@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

setup_fake_docker() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin" "$BATS_TEST_TMPDIR/containers"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
set -u
LOG="${BATS_TEST_TMPDIR}/docker.log"
STATE="${BATS_TEST_TMPDIR}/containers"
printf '%s\n' "$*" >> "$LOG"
case "${1:-}" in
  inspect)
    name="${!#}"
    [ -d "$STATE/$name" ] || exit 1
    printf 'true %s %s\n' "$(cat "$STATE/$name/spec")" "$(cat "$STATE/$name/start")"
    ;;
  image)
    fmt=""
    for a in "$@"; do case "$a" in *Entrypoint*|*Cmd*) fmt="$a" ;; esac; done
    case "$fmt" in
      *Entrypoint*) [ -n "${FAKE_ENTRYPOINT:-}" ] && printf '%s\n' $FAKE_ENTRYPOINT ;;
      *Cmd*) [ -n "${FAKE_CMD:-}" ] && printf '%s\n' $FAKE_CMD ;;
    esac
    exit 0
    ;;
  run)
    detached=0 name="" spec="" start=""
    prev=""
    for a in "$@"; do
      [ "$a" = "-d" ] && detached=1
      [ "$prev" = "--name" ] && name="$a"
      case "$prev:$a" in
        --label:eidolons.spec=*) spec="${a#eidolons.spec=}" ;;
        --label:eidolons.session.start=*) start="${a#eidolons.session.start=}" ;;
      esac
      prev="$a"
    done
    if [ "$detached" -eq 1 ]; then
      if [ "${FAKE_RUN_FAIL:-0}" = "1" ]; then
        echo "docker: Error response from daemon: simulated" >&2
        exit 125
      fi
      mkdir -p "$STATE/$name"
      printf '%s' "$spec" > "$STATE/$name/spec"
      printf '%s' "$start" > "$STATE/$name/start"
      echo "f00dcafe0123456789"
    else
      echo "DIRECT-RUN"
    fi
    ;;
  exec) echo "EXEC-STDOUT" ;;
  rm)
    for a in "$@"; do rm -rf "${STATE:?}/$a" 2>/dev/null; done
    ;;
  ps) : ;;
esac
exit 0
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
}

setup() {
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"
  setup_fake_docker
  export FAKE_ENTRYPOINT="/tonberry"
  unset FAKE_CMD FAKE_RUN_FAIL EIDOLONS_MCP_CONTAINER_SCOPE || true
  # Stand-in session anchor. Detach its fds (incl. bats' fd 3) or bats waits
  # for it to exit before finishing the test.
  sleep 60 </dev/null >/dev/null 2>&1 3>&- &
  ANCHOR=$!
  export EIDOLONS_MCP_SESSION_PID="$ANCHOR"
  export EIDOLONS_MCP_SESSION_HOST="claude"
  export EIDOLONS_MCP_WATCH_INTERVAL=1
  DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
}

teardown() {
  kill "$ANCHOR" 2>/dev/null || true
}

# launch_tonberry [EXTRA LAUNCHER OPTS...] — stdout only (stderr discarded).
launch_tonberry() {
  bash "$LAUNCH" tonberry "$@" -- run --rm -i --user 1000:1000 \
    --label eidolons.project=demo --cpus 0.50 --memory 256m \
    -w /work "$TON_IMAGE" serve 2>/dev/null
}

@test "first client creates one named, labelled session container and execs into it" {
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  # stdout is the MCP channel: only the exec'd server's bytes reach it.
  [ "$output" = "EXEC-STDOUT" ]

  local run_line
  run_line="$(grep '^run -d -i ' "$DOCKER_LOG")"
  [[ "$run_line" == *"--name eidolons-demo-tonberry-claude-${ANCHOR} "* ]]
  [[ "$run_line" == *"--label eidolons.scope=session"* ]]
  [[ "$run_line" == *"--label eidolons.mcp=tonberry"* ]]
  [[ "$run_line" == *"--label eidolons.session.pid=${ANCHOR}"* ]]
  [[ "$run_line" == *"--label eidolons.session.host=claude"* ]]
  # Rendered flags survive; per-connection flags do not.
  [[ "$run_line" == *"--user 1000:1000"* ]]
  [[ "$run_line" == *"--cpus 0.50 --memory 256m"* ]]
  [[ "$run_line" == *"-w /work"* ]]
  [[ "$run_line" != *"--rm"* ]]
  # server keepalive: the image's own serve command is PID 1.
  [[ "$run_line" == *"$TON_IMAGE serve" ]]
  grep -q "^exec -i eidolons-demo-tonberry-claude-${ANCHOR} /tonberry serve$" "$DOCKER_LOG"
}

@test "sub-agent clients of the same session reuse the container (no second create)" {
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  [ "$(grep -c '^run -d -i ' "$DOCKER_LOG")" -eq 1 ]
  [ "$(grep -c '^exec -i ' "$DOCKER_LOG")" -eq 3 ]
}

@test "a different session gets its own container" {
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  sleep 60 </dev/null >/dev/null 2>&1 3>&- &
  local other=$!
  EIDOLONS_MCP_SESSION_PID="$other" run launch_tonberry --keepalive server
  kill "$other" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(grep -c '^run -d -i ' "$DOCKER_LOG")" -eq 2 ]
  grep -q -- "--name eidolons-demo-tonberry-claude-${other} " "$DOCKER_LOG"
}

@test "a changed spec (new digest or limits) replaces the session container" {
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  run bash "$LAUNCH" tonberry --keepalive server -- run --rm -i --user 1000:1000 \
    --label eidolons.project=demo --cpus 1.00 --memory 512m -w /work "$TON_IMAGE" serve
  [ "$status" -eq 0 ]
  [ "$(grep -c '^run -d -i ' "$DOCKER_LOG")" -eq 2 ]
  grep -q "^rm -f eidolons-demo-tonberry-claude-${ANCHOR}$" "$DOCKER_LOG"
}

@test "shell keepalive idles /bin/sh as PID 1 and execs entrypoint + serve command" {
  export FAKE_ENTRYPOINT="uv run --no-sync"
  run bash "$LAUNCH" crystalium --keepalive shell -- run --rm -i \
    --label eidolons.project=demo -e CRYSTALIUM_CALLER_TIER=T1 "$CRY_IMAGE" python -m crystalium serve
  [ "$status" -eq 0 ]
  local run_line
  run_line="$(grep '^run -d -i ' "$DOCKER_LOG")"
  [[ "$run_line" == *"--entrypoint /bin/sh $CRY_IMAGE -c "* ]]
  [[ "$run_line" != *"crystalium serve"* ]]
  grep -q "^exec -i eidolons-demo-crystalium-claude-${ANCHOR} uv run --no-sync python -m crystalium serve$" "$DOCKER_LOG"
}

@test "empty serve command falls back to the image CMD" {
  export FAKE_CMD="serve --repo /repo"
  export FAKE_ENTRYPOINT="atlas-aci"
  run bash "$LAUNCH" atlas-aci --keepalive shell -- run --rm -i \
    --label eidolons.project=demo "$TON_IMAGE"
  [ "$status" -eq 0 ]
  grep -q "^exec -i eidolons-demo-atlas-aci-claude-${ANCHOR} atlas-aci serve --repo /repo$" "$DOCKER_LOG"
}

@test "anchor is the topmost process of the nearest host kind (never a foreign host above it)" {
  unset EIDOLONS_MCP_SESSION_PID EIDOLONS_MCP_SESSION_HOST
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  # Chain: <launcher parent> -> 100 bash -> 90 claude (-p sub-agent) -> 80 zsh
  #        -> 70 claude (main session) -> 60 Cursor (IDE hosting the terminal).
  cat > "$fake_bin/ps" <<'SHIM'
#!/usr/bin/env bash
pid="" fmt=""
while [ $# -gt 0 ]; do
  case "$1" in -p) pid="$2"; shift 2 ;; -o) fmt="$2"; shift 2 ;; *) shift ;; esac
done
case "$fmt" in
  lstart=) echo "Sun Nov  8 00:00:00 2026"; exit 0 ;;
esac
case "$pid" in
  100) echo "   90 /bin/bash -c something" ;;
  90)  echo "   80 /usr/local/bin/claude -p review" ;;
  80)  echo "   70 -zsh" ;;
  70)  echo "   60 /usr/local/bin/claude --resume" ;;
  60)  echo "    1 /Applications/Cursor.app/Contents/MacOS/Cursor" ;;
  *)   echo "  100 bats-runner" ;;
esac
SHIM
  chmod +x "$fake_bin/ps"
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  grep -q -- "--name eidolons-demo-tonberry-claude-70 " "$DOCKER_LOG"
}

@test "no host agent in the ancestry anchors on the direct MCP client" {
  unset EIDOLONS_MCP_SESSION_PID EIDOLONS_MCP_SESSION_HOST
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  cat > "$fake_bin/ps" <<'SHIM'
#!/usr/bin/env bash
case "$*" in *lstart=*) echo "Sun Nov  8 00:00:00 2026"; exit 0 ;; esac
echo "    1 /usr/bin/some-ci-runner"
SHIM
  chmod +x "$fake_bin/ps"
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  grep -q -- "--name eidolons-demo-tonberry-client-" "$DOCKER_LOG"
  grep -q -- "--label eidolons.session.host=client" "$DOCKER_LOG"
}

@test "the session watcher removes the session's containers once the anchor exits" {
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  kill "$ANCHOR"
  local i=0
  while [ "$i" -lt 50 ] && ! grep -q '^ps -aq --filter label=eidolons.session=claude-' "$DOCKER_LOG"; do
    sleep 0.2
    i=$((i + 1))
  done
  grep -q '^ps -aq --filter label=eidolons.session=claude-' "$DOCKER_LOG"
}

@test "container_scope=client env escape hatch runs the rendered argv verbatim" {
  EIDOLONS_MCP_CONTAINER_SCOPE=client run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  [ "$output" = "DIRECT-RUN" ]
  grep -q "^run --rm -i --user 1000:1000 --label eidolons.project=demo --cpus 0.50 --memory 256m -w /work $TON_IMAGE serve$" "$DOCKER_LOG"
  run grep -q '^run -d' "$DOCKER_LOG"
  [ "$status" -ne 0 ]
}

@test "argv without a pinned digest is passed through untouched" {
  run bash "$LAUNCH" custom -- run --rm -i example:latest serve
  [ "$status" -eq 0 ]
  grep -q '^run --rm -i example:latest serve$' "$DOCKER_LOG"
  run grep -q '^run -d' "$DOCKER_LOG"
  [ "$status" -ne 0 ]
}

@test "session container create failure fails open to a per-client container" {
  export FAKE_RUN_FAIL=1
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  [ "$output" = "DIRECT-RUN" ]
  grep -q "^run --rm -i --user 1000:1000 " "$DOCKER_LOG"
  [ ! -d "$EIDOLONS_HOME/run/mcp/eidolons-demo-tonberry-claude-${ANCHOR}.lock" ]
}

@test "launcher holds no lock after a successful attach" {
  run launch_tonberry --keepalive server
  [ "$status" -eq 0 ]
  [ ! -d "$EIDOLONS_HOME/run/mcp/eidolons-demo-tonberry-claude-${ANCHOR}.lock" ]
}
