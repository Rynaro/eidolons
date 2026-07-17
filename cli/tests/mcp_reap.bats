#!/usr/bin/env bats
#
# cli/tests/mcp_reap.bats — tests for 'eidolons mcp reap' (ESL change
# mcp-reap-command). One test per acceptance check (AC-001..AC-020).
#
# Inline fake-docker + fake-ps harness (per-file convention, do NOT lift to
# helpers.bash — model on cli/tests/mcp_images.bats lines 24-90).
#
# Fixture model:
#   docker-ps.tsv  "id<TAB>name<TAB>psimage<TAB>project<TAB>created<TAB>fullimage"
#     - psimage  is what `docker ps --format {{.Image}}` would print (unused
#       by the reaper's own logic beyond a display fallback — kept distinct
#       from fullimage on purpose, mirroring the real-world short-vs-full
#       digest split verified live: `docker ps --format {{.Image}}` prints a
#       short form that never matches a client's process-args image token).
#     - fullimage is what `docker inspect -f '{{.Config.Image}}'` returns —
#       the exact reference a `docker run` client's args carry, and the
#       signature the guard's rank-bijection groups on.
#   ps-table.txt   "pid ppid etime args..." — one process per line. Consumed
#     verbatim by the fake `ps` regardless of invocation args (the reaper's
#     own `ps -eo ...` vs `-Ao ...` branching is irrelevant to a fixture that
#     always returns the same table).
#
# Control env-vars read at shim invocation time:
#   FAKE_DOCKER_INFO_RESULT   ok (default) / fail
#
# Test-only seams honored by the reaper itself (see mcp_reap.sh):
#   EIDOLONS_REAP_SELF_PID    roots the process-parent walk (stand-in for $$)
#   CLAUDECODE                set/unset selects guard-active-path vs "none"
#
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".

load helpers

REAP_SH="$EIDOLONS_ROOT/cli/src/mcp_reap.sh"

# ─── Fake-docker + fake-ps harness ─────────────────────────────────────────

setup_fake_docker() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  : > "$BATS_TEST_TMPDIR/docker-ps.tsv"

  cat > "$fake_bin/docker" <<'SHIM'
#!/usr/bin/env bash
set -u

DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
PS_TSV="${BATS_TEST_TMPDIR}/docker-ps.tsv"
INFO_RESULT="${FAKE_DOCKER_INFO_RESULT:-ok}"

subcmd="${1:-}"
case "$subcmd" in
  info)
    printf 'info\n' >> "$DOCKER_LOG"
    [ "$INFO_RESULT" = "ok" ] && exit 0 || exit 1
    ;;
  ps)
    shift
    filter=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --filter) filter="$2"; shift 2 ;;
        --format) shift 2 ;;
        *) shift ;;
      esac
    done
    printf 'ps --filter %s\n' "$filter" >> "$DOCKER_LOG"
    [ -f "$PS_TSV" ] || exit 0
    case "$filter" in
      label=eidolons.project=*)
        slug="${filter#label=eidolons.project=}"
        awk -F'\t' -v s="$slug" '$4 == s {print $1"\t"$2"\t"$3"\t"$4"\t"$5}' "$PS_TSV"
        ;;
      label=eidolons.project)
        awk -F'\t' '$4 != "" {print $1"\t"$2"\t"$3"\t"$4"\t"$5}' "$PS_TSV"
        ;;
    esac
    exit 0
    ;;
  inspect)
    shift
    id=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -f|--format) shift 2 ;;
        *) id="$1"; shift ;;
      esac
    done
    printf 'inspect %s\n' "$id" >> "$DOCKER_LOG"
    [ -f "$PS_TSV" ] || exit 1
    row="$(awk -F'\t' -v i="$id" '$1 == i {print; exit}' "$PS_TSV")"
    [ -z "$row" ] && exit 1
    created="$(printf '%s' "$row" | awk -F'\t' '{print $5}')"
    fullimg="$(printf '%s' "$row" | awk -F'\t' '{print $6}')"
    printf '%s\t%s\n' "$created" "$fullimg"
    exit 0
    ;;
  stop)
    shift
    name="${1:-}"
    printf 'stop %s\n' "$name" >> "$DOCKER_LOG"
    exit 0
    ;;
  *)
    printf '%s\n' "$*" >> "$DOCKER_LOG"
    exit 0
    ;;
esac
SHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
}

setup_fake_ps() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  : > "$BATS_TEST_TMPDIR/ps-table.txt"

  cat > "$fake_bin/ps" <<'SHIM'
#!/usr/bin/env bash
set -u
PS_TABLE="${BATS_TEST_TMPDIR}/ps-table.txt"
[ -f "$PS_TABLE" ] && cat "$PS_TABLE"
exit 0
SHIM
  chmod +x "$fake_bin/ps"
  export PATH="$fake_bin:$PATH"
}

# add_container ID NAME PSIMAGE PROJECT CREATED FULLIMAGE
add_container() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$BATS_TEST_TMPDIR/docker-ps.tsv"
}

# add_process PID PPID ETIME ARGS...
add_process() {
  local pid="$1" ppid="$2" etime="$3"
  shift 3
  printf '%s %s %s %s\n' "$pid" "$ppid" "$etime" "$*" >> "$BATS_TEST_TMPDIR/ps-table.txt"
}

# iso_ago SECONDS — an ISO8601 UTC timestamp SECONDS in the past. GNU date
# first, BSD `date -r` fallback (portable across the macos-latest CI job).
iso_ago() {
  local secs_ago="$1" epoch
  epoch=$(( $(date +%s) - secs_ago ))
  if date -u -d "@${epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null; then
    return 0
  fi
  date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ'
}

# Standard current-session process chain: self (EIDOLONS_REAP_SELF_PID=500)
# -> claude (pid 100, ppid 1). Used by every "guard active/indeterminate"
# scenario except AC-013, which deliberately omits the claude row.
add_self_chain() {
  add_process 500 100 00:00:01 bash "$REAP_SH"
  add_process 100 1 10:00:00 claude
}

DOCKER_LOG_FILE=""

setup() {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"

  # Fixed project dirname so project_slug() resolves deterministically to
  # "eidolons" (matches this repo's own real .mcp.json label value).
  TEST_PROJECT="$BATS_TEST_TMPDIR/eidolons"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  export FAKE_DOCKER_INFO_RESULT=ok
  unset CLAUDECODE || true
  unset EIDOLONS_REAP_SELF_PID || true
  unset CLAUDE_CODE_EXECPATH || true

  setup_fake_docker
  setup_fake_ps

  DOCKER_LOG_FILE="$BATS_TEST_TMPDIR/docker.log"
}

teardown() {
  cd "$EIDOLONS_ROOT"
}

# ─── AC-001: docker CLI absent ─────────────────────────────────────────────

@test "AC-001: docker CLI absent -> exit 0, no docker stop ever logged" {
  # Mirror every executable EXCEPT docker onto an exclusive PATH (a bare
  # `rm -f fake-bin/docker` would leak a real host docker) — same technique
  # as mcp_images.bats S11.
  local nodoc="$BATS_TEST_TMPDIR/nodoc-bin"
  mkdir -p "$nodoc"
  local _dirs d f b
  IFS=':' read -ra _dirs <<< "$PATH"
  for d in "${_dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -e "$f" ] || continue
      b="$(basename "$f")"
      [ "$b" = "docker" ] && continue
      [ -e "$nodoc/$b" ] || ln -s "$f" "$nodoc/$b" 2>/dev/null || true
    done
  done

  local _saved_path="$PATH"
  PATH="$nodoc"
  run bash "$REAP_SH" --yes
  PATH="$_saved_path"

  [ "$status" -eq 0 ]
  run bash -c "grep -c '^stop' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
}

# ─── AC-002: docker daemon unreachable ─────────────────────────────────────

@test "AC-002: docker daemon unreachable -> exit 0, stops nothing" {
  export FAKE_DOCKER_INFO_RESULT=fail
  add_container c1 stale-mcp shortimg eidolons "$(iso_ago 3600)" ghcr.io/x/y@sha256:zzzz

  run bash "$REAP_SH" --yes
  [ "$status" -eq 0 ]

  run bash -c "grep -c '^stop' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
}

# ─── AC-003 / AC-004: the core safety invariant ────────────────────────────
#
# CURRENT_CLAUDE_PID (100) owns one crystalium client (pid 601) rank-paired
# by CreatedAt-ascending / start-order-descending to container
# cur-crystalium (created LATER). An other-session client (pid 602, ppid
# 200, started earlier / larger etime) pairs to old-crystalium (created
# EARLIER). Only old-crystalium may ever be stopped.

setup_core_safety_scenario() {
  export CLAUDECODE=1
  export EIDOLONS_REAP_SELF_PID=500
  add_self_chain
  add_process 601 100 00:10:00 docker run --rm -i --label eidolons.project=eidolons -v /a:/b \
    ghcr.io/rynaro/crystalium@sha256:aaaa python -m crystalium serve
  add_process 602 200 02:00:00 docker run --rm -i --label eidolons.project=eidolons -v /a:/b \
    ghcr.io/rynaro/crystalium@sha256:aaaa python -m crystalium serve

  add_container c-old old-crystalium shortimg eidolons "2024-01-01T00:00:00Z" ghcr.io/rynaro/crystalium@sha256:aaaa
  add_container c-cur cur-crystalium shortimg eidolons "2024-01-01T02:00:00Z" ghcr.io/rynaro/crystalium@sha256:aaaa
}

@test "AC-003: current-session container (cur-crystalium) is never passed to docker stop" {
  setup_core_safety_scenario
  run bash "$REAP_SH" --yes
  [ "$status" -eq 0 ]

  run bash -c "grep -c '^stop cur-crystalium\$' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
}

@test "AC-004: other-session container (old-crystalium) is stopped exactly once" {
  setup_core_safety_scenario
  run bash "$REAP_SH" --yes
  [ "$status" -eq 0 ]

  run bash -c "grep -c '^stop old-crystalium\$' '$DOCKER_LOG_FILE'"
  [ "$output" -eq 1 ]
}

# ─── AC-005: preview default (neither --yes nor --dry-run) ────────────────

@test "AC-005: no flags -> preview only, lists the would-reap set, stops nothing" {
  add_container c1 other-stale shortimg eidolons "$(iso_ago 3600)" ghcr.io/x/y@sha256:p5

  run bash "$REAP_SH"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "other-stale" ]]

  run bash -c "grep -c '^stop' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
}

# ─── AC-006: --dry-run wins over --yes ─────────────────────────────────────

@test "AC-006: --dry-run --yes together -> dry-run wins, stops nothing" {
  add_container c1 other-stale shortimg eidolons "$(iso_ago 3600)" ghcr.io/x/y@sha256:p6

  run bash "$REAP_SH" --dry-run --yes
  [ "$status" -eq 0 ]

  run bash -c "grep -c '^stop' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
}

# ─── AC-007: --project restricts to one slug ───────────────────────────────

@test "AC-007: --project other -> only other-slug containers are stoppable" {
  add_container c1 eidolons-mcp shortimg eidolons "$(iso_ago 3600)" ghcr.io/x/y@sha256:p7a
  add_container c2 other-mcp shortimg other "$(iso_ago 3600)" ghcr.io/x/y@sha256:p7b

  run bash "$REAP_SH" --yes --project other
  [ "$status" -eq 0 ]

  run bash -c "grep -c '^stop eidolons-mcp\$' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
  run bash -c "grep -c '^stop other-mcp\$' '$DOCKER_LOG_FILE'"
  [ "$output" -eq 1 ]
}

# ─── AC-008 / AC-009: --older-than age filter ──────────────────────────────

@test "AC-008: a container created 30s ago is not reaped under --older-than 10m" {
  add_container c1 young-mcp shortimg eidolons "$(iso_ago 30)" ghcr.io/x/y@sha256:p8
  add_container c2 old-enough-mcp shortimg eidolons "$(iso_ago 7200)" ghcr.io/x/y@sha256:p9

  run bash -c "bash '$REAP_SH' --yes --older-than 10m --json 2>/dev/null"
  [ "$status" -eq 0 ]
  local json_output="$output"

  run bash -c "grep -c '^stop young-mcp\$' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]

  run jq -e '[.skipped[] | select(.name == "young-mcp" and .reason == "too-young")] | length == 1' <<< "$json_output"
  [ "$status" -eq 0 ]
}

@test "AC-009: a container created 2h ago IS reaped under --older-than 10m" {
  add_container c1 young-mcp shortimg eidolons "$(iso_ago 30)" ghcr.io/x/y@sha256:p8
  add_container c2 old-enough-mcp shortimg eidolons "$(iso_ago 7200)" ghcr.io/x/y@sha256:p9

  run bash "$REAP_SH" --yes --older-than 10m
  [ "$status" -eq 0 ]

  run bash -c "grep -c '^stop old-enough-mcp\$' '$DOCKER_LOG_FILE'"
  [ "$output" -eq 1 ]
}

# ─── AC-010: --json schema ──────────────────────────────────────────────────

@test "AC-010: --json emits a valid eidolons/mcp-reap.v1 object" {
  add_container c1 some-mcp shortimg eidolons "$(iso_ago 3600)" ghcr.io/x/y@sha256:p10

  run bash -c "bash '$REAP_SH' --json 2>/dev/null"
  [ "$status" -eq 0 ]

  run jq -e '.schema=="eidolons/mcp-reap.v1" and (.guard.status|type=="string") and (.reap|type=="array") and (.protected|type=="array")' <<< "$output"
  [ "$status" -eq 0 ]
}

# ─── AC-011: only current-session containers present ───────────────────────

@test "AC-011: only current-session containers exist -> nothing reaped" {
  export CLAUDECODE=1
  export EIDOLONS_REAP_SELF_PID=500
  add_self_chain
  add_process 601 100 00:05:00 docker run --rm -i --label eidolons.project=eidolons -v /a:/b \
    ghcr.io/rynaro/crystalium@sha256:cccc python -m crystalium serve
  add_container c1 cur-only-mcp shortimg eidolons "2024-01-01T00:00:00Z" ghcr.io/rynaro/crystalium@sha256:cccc

  run bash -c "bash '$REAP_SH' --yes --json 2>/dev/null"
  [ "$status" -eq 0 ]
  local json_output="$output"

  run bash -c "grep -c '^stop' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]

  run jq -e '.reap == []' <<< "$json_output"
  [ "$status" -eq 0 ]
}

# ─── AC-012: idempotent second run ─────────────────────────────────────────

@test "AC-012: a second run after a successful reap stops nothing new" {
  setup_core_safety_scenario

  run bash "$REAP_SH" --yes
  [ "$status" -eq 0 ]
  run bash -c "grep -c '^stop old-crystalium\$' '$DOCKER_LOG_FILE'"
  [ "$output" -eq 1 ]

  # Repoint fake `docker ps` to the post-reap set: old-crystalium is gone.
  : > "$BATS_TEST_TMPDIR/docker-ps.tsv"
  add_container c-cur cur-crystalium shortimg eidolons "2024-01-01T02:00:00Z" ghcr.io/rynaro/crystalium@sha256:aaaa

  run bash "$REAP_SH" --yes
  [ "$status" -eq 0 ]

  # Still exactly one stop line for old-crystalium (from the FIRST run only).
  run bash -c "grep -c '^stop old-crystalium\$' '$DOCKER_LOG_FILE'"
  [ "$output" -eq 1 ]
  run bash -c "grep -c '^stop cur-crystalium\$' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
}

# ─── AC-013: CLAUDECODE set, no resolvable claude ancestor ────────────────

@test "AC-013: CLAUDECODE set but no claude ancestor resolves -> indeterminate, protect-all" {
  export CLAUDECODE=1
  export EIDOLONS_REAP_SELF_PID=500
  # Deliberately NO claude row — self's parent chain hits PID 1 unmatched.
  add_process 500 1 00:00:01 bash "$REAP_SH"
  add_container c1 stale-mcp shortimg eidolons "$(iso_ago 3600)" ghcr.io/x/y@sha256:p13

  run bash -c "bash '$REAP_SH' --yes --json 2>/dev/null"
  [ "$status" -eq 0 ]
  local json_output="$output"

  run bash -c "grep -c '^stop' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]

  run jq -e '.guard.status == "indeterminate"' <<< "$json_output"
  [ "$status" -eq 0 ]
}

# ─── AC-014: --all spans every slug ────────────────────────────────────────

@test "AC-014: --all reaps across every eidolons.project slug" {
  add_container c1 eidolons-mcp shortimg eidolons "$(iso_ago 3600)" ghcr.io/x/y@sha256:p14a
  add_container c2 other-mcp shortimg other "$(iso_ago 3600)" ghcr.io/x/y@sha256:p14b

  run bash "$REAP_SH" --yes --all
  [ "$status" -eq 0 ]

  run bash -c "grep -c '^stop other-mcp\$' '$DOCKER_LOG_FILE'"
  [ "$output" -eq 1 ]
}

# ─── AC-015: unlabeled containers are never candidates ─────────────────────

@test "AC-015: an unlabeled container is never passed to docker stop, even under --all" {
  add_container c1 other-mcp shortimg other "$(iso_ago 3600)" ghcr.io/x/y@sha256:p15a
  add_container c2 unlabeled-mcp shortimg "" "$(iso_ago 3600)" ghcr.io/x/y@sha256:p15b

  run bash "$REAP_SH" --yes --all
  [ "$status" -eq 0 ]

  # Proves reaping actually ran (a labeled container WAS stopped)...
  run bash -c "grep -c '^stop other-mcp\$' '$DOCKER_LOG_FILE'"
  [ "$output" -eq 1 ]
  # ...while the unlabeled one never appears.
  run bash -c "grep -c '^stop unlabeled-mcp\$' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
}

# ─── AC-016: unknown flag ───────────────────────────────────────────────────

@test "AC-016: unknown flag --bogus exits 2" {
  run bash "$REAP_SH" --bogus
  [ "$status" -eq 2 ]
}

# ─── AC-017: malformed --older-than ────────────────────────────────────────

@test "AC-017: malformed --older-than 5x exits 2" {
  run bash "$REAP_SH" --older-than 5x
  [ "$status" -eq 2 ]
}

# ─── AC-018: shellcheck-clean ───────────────────────────────────────────────

@test "AC-018: cli/src/mcp_reap.sh is shellcheck-clean under -S error" {
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not on PATH"
  run shellcheck -x -S error "$EIDOLONS_ROOT/cli/src/mcp_reap.sh"
  [ "$status" -eq 0 ]
}

# ─── AC-019: mcp dispatcher registration ───────────────────────────────────

@test "AC-019: eidolons mcp reap --help exits 0 through the full dispatcher" {
  run "$EIDOLONS_BIN" mcp reap --help
  [ "$status" -eq 0 ]
}

@test "AC-019: mcp.sh registers reap in the case arm, usage block, and error list" {
  local mcpsh="$EIDOLONS_ROOT/cli/src/mcp.sh"
  run grep -E 'reap\)' "$mcpsh"
  [ "$status" -eq 0 ]
  run grep -E '^\s+reap\s' "$mcpsh"
  [ "$status" -eq 0 ]
  run grep -E 'Available subcommands:.*\breap\b' "$mcpsh"
  [ "$status" -eq 0 ]
}

# ─── AC-020: ambiguity-safe over-protect (mid-respawn count mismatch) ──────

@test "AC-020: client/container count mismatch with a cur-session client -> over-protect both" {
  export CLAUDECODE=1
  export EIDOLONS_REAP_SELF_PID=500
  add_self_chain
  # Exactly ONE client for this signature, owned by the current session.
  add_process 701 100 00:05:00 docker run --rm -i --label eidolons.project=eidolons -v /a:/b \
    ghcr.io/rynaro/tonberry@sha256:bbbb serve
  # TWO containers of the same signature (a mid-respawn window).
  add_container c-old respawn-old shortimg eidolons "2024-01-01T00:00:00Z" ghcr.io/rynaro/tonberry@sha256:bbbb
  add_container c-new respawn-new shortimg eidolons "2024-01-01T01:00:00Z" ghcr.io/rynaro/tonberry@sha256:bbbb

  run bash "$REAP_SH" --yes
  [ "$status" -eq 0 ]

  run bash -c "grep -c '^stop respawn-old\$' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
  run bash -c "grep -c '^stop respawn-new\$' '$DOCKER_LOG_FILE' 2>/dev/null || true"
  [ "${output:-0}" -eq 0 ]
}
