#!/usr/bin/env bats
#
# cli/tests/mcp_ps.bats — 'eidolons mcp ps' (session-grouped MCP container view).
#
# Fake docker: `ps --filter label=eidolons.scope=session` prints SESSION_ROWS,
# the legacy listing prints LEGACY_ROWS (one empty eidolons.scope per legacy
# container), and `stats` prints one usage row per session container.

load helpers

PS_SH="$EIDOLONS_ROOT/cli/src/mcp_ps.sh"

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  export EIDOLONS_PS_HOST_ID="test-host"
  mkdir -p "$EIDOLONS_HOME" "$BATS_TEST_TMPDIR/demo"
  cd "$BATS_TEST_TMPDIR/demo"
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  : > "$BATS_TEST_TMPDIR/session.tsv"
  : > "$BATS_TEST_TMPDIR/legacy.txt"
  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
case "${1:-}" in
  info) exit 0 ;;
  ps)
    case "$*" in
      *eidolons.scope=session*) cat "$BATS_TEST_TMPDIR/session.tsv" ;;
      *) cat "$BATS_TEST_TMPDIR/legacy.txt" ;;
    esac
    ;;
  stats)
    shift
    for a in "$@"; do
      case "$a" in --*|'{{'*) continue ;; esac
      printf '%s\t12MiB / 256MiB\t0.10%%\t5\n' "$a"
    done
    ;;
esac
exit 0
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
  sleep 60 </dev/null >/dev/null 2>&1 3>&- &
  ANCHOR=$!
}

teardown() {
  kill "$ANCHOR" 2>/dev/null || true
}

# add_session NAME MCP HOST PID START HOST_ID
add_session() {
  printf '%s\tdemo\t%s\t%s\t%s\t%s\t%s\t2 minutes ago\n' "$1" "$2" "$3" "$4" "$5" "$6" \
    >> "$BATS_TEST_TMPDIR/session.tsv"
}

start_id() {
  ps -o lstart= -p "$1" | cksum | awk '{print $1}'
}

@test "lists a live session's containers with owner, state and usage" {
  add_session "eidolons-demo-tonberry-claude-${ANCHOR}" tonberry claude "$ANCHOR" "$(start_id "$ANCHOR")" test-host
  run bash "$PS_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION"*"STATE"*"CONTAINER"* ]]
  [[ "$output" == *"claude-${ANCHOR}"*"live"*"tonberry"*"eidolons-demo-tonberry-claude-${ANCHOR}"*"12MiB / 256MiB"* ]]
}

@test "a session whose anchor is gone is reported dead" {
  add_session "eidolons-demo-atomos-codex-999999" atomos codex 999999 123 test-host
  run bash "$PS_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex-999999"*"dead"* ]]
}

@test "--json reports containers and the legacy per-client count" {
  add_session "eidolons-demo-tonberry-claude-${ANCHOR}" tonberry claude "$ANCHOR" "$(start_id "$ANCHOR")" test-host
  printf '\n\n' > "$BATS_TEST_TMPDIR/legacy.txt"
  run bash -c "bash '$PS_SH' --json 2>/dev/null"
  [ "$status" -eq 0 ]
  run jq -e '.schema == "eidolons/mcp-ps.v1"
    and .project == "demo"
    and (.containers | length) == 1
    and .containers[0].state == "live"
    and .containers[0].session == "claude-'"$ANCHOR"'"
    and .legacy_per_client_containers == 2' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "--all and --project are mutually exclusive" {
  run bash "$PS_SH" --all --project demo
  [ "$status" -eq 2 ]
}
