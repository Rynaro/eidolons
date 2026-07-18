#!/usr/bin/env bash
# cli/src/mcp_reap.sh — stop stale MCP containers without killing the live session.
#
# ESL change mcp-reap-command. `.mcp.json` runs docker/`--rm -i` stdio MCP
# servers; a container lives exactly as long as its `docker run` client keeps
# stdin open, so abandoned Claude Code sessions (and daemon-prewarmed spares)
# leave live-but-unwanted containers behind forever. 'reap' lists and (on
# explicit confirm) stops labeled stale containers — but NEVER a container
# the running agent is using mid-task.
#
# Usage: eidolons mcp reap [--dry-run] [-y|--yes] [--all] [--project <slug>]
#                           [--older-than <dur>] [--json] [-h|--help]
#
# Exit codes:
#   0  success — reaped | nothing-to-reap | docker-absent | guard-indeterminate | any preview
#   2  usage error — unknown flag | malformed --older-than | --all with --project
#
# THE LOAD-BEARING INVARIANT: the current session's containers are NEVER
# passed to `docker stop`. The guard resolves CURRENT_CLAUDE_PID by walking
# the process-parent chain from $$ (overridable via the test-only seam
# EIDOLONS_REAP_SELF_PID) to the nearest ancestor `claude`; the current
# session's MCP `docker run` clients are its direct children; a per-signature
# rank-bijection (client start-order == container creation-order) marks the
# current session's containers PROTECTED. Any ambiguity — count mismatch, a
# start-order/CreatedAt tie, an unresolved guard, or no `ps` at all — FAILS
# SAFE: protect every candidate, stop nothing, exit 0. Preview (neither --yes
# nor --dry-run) is the default; only --yes actually stops anything, and
# --dry-run always wins over a stray --yes.
#
# Container identity is label-only: `eidolons.project=<slug>` (bare
# `eidolons.project` under --all). Nothing without the label is ever a
# candidate — an unlabeled container (e.g. a legacy atlas-aci wiring that
# predates the label) is invisible to reap. This is the safe direction: it is
# never wrongly stopped, but must be cleaned up manually.
#
# stdout/stderr: all human/log output goes to stderr via say/ok/info/warn/die.
# stdout is reserved for --json (schema eidolons/mcp-reap.v1) — several
# callers capture stdout, so nothing else may write there.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile,
# no &>>. See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

usage() {
  cat >&2 <<EOF
eidolons mcp reap — stop stale MCP containers without killing the live session

Usage: eidolons mcp reap [options]

Options:
  --dry-run            Preview the reap set; never invoke docker stop. Wins over --yes.
  -y, --yes            Actually stop the reap set. Without it (and without --dry-run),
                        reap PREVIEWS and stops nothing (safe default for a destructive op).
  --all                Consider labeled MCP containers across EVERY eidolons.project slug.
                        Mutually exclusive with --project. (Default: current project only.)
  --project <slug>     Restrict to containers labeled eidolons.project=<slug>.
                        Default: the current project slug (project_slug of cwd).
  --older-than <dur>   Only reap containers created more than <dur> ago (Ns|Nm|Nh|Nd).
                        Default: 0 (any age, still subject to the session guard).
  --json               Emit a machine-readable JSON object (schema eidolons/mcp-reap.v1)
                        on stdout; all human logs stay on stderr.
  -h, --help           Show this help.

Exit codes:
  0  success — reaped, nothing-to-reap, docker absent, guard indeterminate, or any preview
  2  usage error (unknown flag, bad --older-than, --all combined with --project)

Safety default = preview. With neither --yes nor --dry-run, reap lists what it
would stop and stops nothing. Only --yes (without --dry-run) executes docker stop.

The current session's containers are NEVER passed to docker stop (see the
script header for the guard algorithm). Any ambiguity fails safe: protect
every candidate, stop nothing, exit 0.

Known gap: unlabeled containers (e.g. a legacy atlas-aci install predating
the eidolons.project label) are never candidates — safe, but invisible to
reap. Clean those up manually with 'docker stop <name>'.
EOF
}

# ─── Small pure helpers ────────────────────────────────────────────────────

# _reap_count_lines STR — count non-empty lines in a newline-separated string.
# Avoids the `grep -c` "no match -> exit 1" pitfall under `set -e`.
_reap_count_lines() {
  local s="$1"
  [ -z "$s" ] && { printf '0'; return 0; }
  # length>0 (not a bare END{print NR}): every accumulator string here is
  # itself already newline-terminated (each append ends in "\n"), so the
  # extra "\n" printf appends produces one trailing blank line that a plain
  # NR count would over-count by one.
  printf '%s\n' "$s" | awk 'length>0{c++} END{print c+0}'
}

# _reap_name_in_list NEEDLE LIST — exit 0 if NEEDLE is a line in LIST.
_reap_name_in_list() {
  local needle="$1" list="$2" x
  while IFS= read -r x; do
    [ -z "$x" ] && continue
    [ "$x" = "$needle" ] && return 0
  done <<< "$list"
  return 1
}

# _reap_dur_to_seconds DUR — Ns|Nm|Nh|Nd -> seconds on stdout, rc 0.
# Malformed input -> rc 1, nothing printed. Uses 10#$n to avoid printf's
# octal reinterpretation of a leading-zero numeral (e.g. "008").
_reap_dur_to_seconds() {
  local dur="$1" n mult
  case "$dur" in
    *[0-9]s) n="${dur%s}"; mult=1 ;;
    *[0-9]m) n="${dur%m}"; mult=60 ;;
    *[0-9]h) n="${dur%h}"; mult=3600 ;;
    *[0-9]d) n="${dur%d}"; mult=86400 ;;
    *) return 1 ;;
  esac
  case "$n" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%d' $(( (10#$n) * mult ))
  return 0
}

# _reap_etime_to_seconds ETIME — ps etime ([[DD-]HH:]MM:SS) -> seconds.
# Bash 3.2 safe; 10#$x guards against octal reinterpretation of "08"/"09".
_reap_etime_to_seconds() {
  local etime="$1" days=0 hms h=0 m=0 s=0 rest
  case "$etime" in
    *-*) days="${etime%%-*}"; hms="${etime#*-}" ;;
    *)   hms="$etime" ;;
  esac
  case "$hms" in
    *:*:*)
      h="${hms%%:*}"
      rest="${hms#*:}"
      m="${rest%%:*}"
      s="${rest#*:}"
      ;;
    *:*)
      m="${hms%%:*}"
      s="${hms#*:}"
      ;;
    *)
      s="$hms"
      ;;
  esac
  [ -z "$days" ] && days=0
  [ -z "$h" ] && h=0
  [ -z "$m" ] && m=0
  [ -z "$s" ] && s=0
  case "$days$h$m$s" in
    *[!0-9]*) printf '0'; return 0 ;;
  esac
  printf '%d' $(( (10#$days * 86400) + (10#$h * 3600) + (10#$m * 60) + 10#$s ))
}

# _reap_iso_to_epoch ISO — parse a docker `.Created`-style ISO8601 timestamp
# to epoch seconds on stdout, rc 0. GNU `date -d` first, BSD `date -jf`
# fallback. rc 1 + nothing printed when neither backend can parse it (P1 —
# never fatal; callers treat an unresolved age as "unknown", which fails the
# age filter safe, i.e. excluded from the reap set).
_reap_iso_to_epoch() {
  local iso="$1" epoch trimmed
  if epoch="$(date -u -d "$iso" '+%s' 2>/dev/null)"; then
    printf '%s' "$epoch"
    return 0
  fi
  trimmed="$(printf '%s' "$iso" | sed -E 's/\.[0-9]+Z$/Z/')"
  trimmed="${trimmed%Z}+0000"
  if epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$trimmed" '+%s' 2>/dev/null)"; then
    printf '%s' "$epoch"
    return 0
  fi
  return 1
}

# _reap_self_pid — the reaper's own PID, overridable by the test-only seam
# EIDOLONS_REAP_SELF_PID (roots the fake-ps process walk deterministically).
_reap_self_pid() {
  if [ -n "${EIDOLONS_REAP_SELF_PID:-}" ]; then
    printf '%s' "$EIDOLONS_REAP_SELF_PID"
  else
    printf '%s' "$$"
  fi
}

# _reap_ps_snapshot — one process-table snapshot: "pid ppid etime args...".
# Linux form first, BSD/macOS fallback second. rc 1 + empty stdout when
# neither backend produces output (no `ps`, or a hardened container without
# /proc) — callers treat this as guard-indeterminate.
_reap_ps_snapshot() {
  local out
  if out="$(ps -eo pid=,ppid=,etime=,args= 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  if out="$(ps -Ao pid=,ppid=,etime=,command= 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  return 1
}

# _reap_ps_row_for_pid PID SNAPSHOT — "ppid<TAB>args" for one pid, or empty.
_reap_ps_row_for_pid() {
  local pid="$1" snapshot="$2"
  awk -v p="$pid" '
    $1 == p {
      ppid = $2
      out = ""
      for (i = 4; i <= NF; i++) { out = out (out == "" ? "" : " ") $i }
      print ppid "\t" out
      exit
    }
  ' <<< "$snapshot"
}

# _reap_resolve_claude_pid SNAPSHOT — walk the parent chain from
# _reap_self_pid, at most 24 hops or until PID 1, to the nearest ancestor
# whose args basename is "claude" (or matches $CLAUDE_CODE_EXECPATH exactly).
# Prints the resolved PID + rc 0 on success; empty + rc 1 when unresolved.
_reap_resolve_claude_pid() {
  local snapshot="$1" pid hops row ppid args first base
  pid="$(_reap_self_pid)"
  hops=0
  while [ "$hops" -lt 24 ] && [ -n "$pid" ] && [ "$pid" != "1" ]; do
    row="$(_reap_ps_row_for_pid "$pid" "$snapshot")"
    [ -z "$row" ] && return 1
    ppid="${row%%$'\t'*}"
    args="${row#*$'\t'}"
    first="${args%% *}"
    base="${first##*/}"
    if [ "$base" = "claude" ] || { [ -n "${CLAUDE_CODE_EXECPATH:-}" ] && [ "$first" = "$CLAUDE_CODE_EXECPATH" ]; }; then
      printf '%s' "$pid"
      return 0
    fi
    pid="$ppid"
    hops=$(( hops + 1 ))
  done
  return 1
}

# _reap_list_clients SNAPSHOT — every process whose args look like
# "docker ... run ..." carrying "eidolons.project=", any PPID. Emits
# "pid<TAB>ppid<TAB>etime<TAB>args" per match (raw etime, not yet seconds).
_reap_list_clients() {
  local snapshot="$1"
  awk '
    {
      pid = $1; ppid = $2; etime = $3
      out = ""
      for (i = 4; i <= NF; i++) { out = out (out == "" ? "" : " ") $i }
      args = out
      n = split(args, toks, " ")
      first = (n >= 1) ? toks[1] : ""
      m = split(first, parts, "/")
      base = parts[m]
      if (base == "docker" && index(args, " run") > 0 && index(args, "eidolons.project=") > 0) {
        print pid "\t" ppid "\t" etime "\t" args
      }
    }
  ' <<< "$snapshot"
}

# _reap_build_clients SNAPSHOT — "pid<TAB>ppid<TAB>etime_seconds<TAB>signature"
# per MCP client process on the host. signature is the image@sha256:... token.
_reap_build_clients() {
  local snapshot="$1" raw pid ppid etime args secs sig out=""
  raw="$(_reap_list_clients "$snapshot")"
  [ -z "$raw" ] && { printf ''; return 0; }
  while IFS=$'\t' read -r pid ppid etime args; do
    [ -z "$pid" ] && continue
    secs="$(_reap_etime_to_seconds "$etime")"
    sig="$(printf '%s' "$args" | grep -oE '[^ ]*@sha256:[0-9a-f]+' | head -1 || true)"
    out="${out}${pid}	${ppid}	${secs}	${sig}
"
  done <<< "$raw"
  printf '%s' "$out"
}

# _reap_compute_protected CANDIDATES ALL_CLIENTS CUR_PID — emits one
# container NAME per line for every container in CANDIDATES that the
# per-signature rank-bijection (or the ambiguity-safe over-protect rule)
# marks as belonging to the current session.
#
# CANDIDATES rows: id name image project created age (tab-separated).
# ALL_CLIENTS rows: pid ppid etime_seconds signature (tab-separated).
_reap_compute_protected() {
  local candidates="$1" all_clients="$2" cur_pid="$3"
  local sigs sig protected=""
  sigs="$(printf '%s\n' "$candidates" | awk -F'\t' '$3 != "" {print $3}' | sort -u)"
  [ -z "$sigs" ] && { printf ''; return 0; }

  while IFS= read -r sig; do
    [ -z "$sig" ] && continue

    local containers_s clients_s n_containers n_clients cur_count tie_created tie_etime ambiguous
    containers_s="$(printf '%s\n' "$candidates" | awk -F'\t' -v s="$sig" '$3 == s' | sort -t $'\t' -k5,5)"
    clients_s="$(printf '%s\n' "$all_clients" | awk -F'\t' -v s="$sig" '$4 == s' | sort -t $'\t' -k3,3nr)"

    n_containers="$(_reap_count_lines "$containers_s")"
    n_clients="$(_reap_count_lines "$clients_s")"
    cur_count="$(printf '%s\n' "$clients_s" | awk -F'\t' -v p="$cur_pid" '$2 == p' | awk 'END{print NR}')"

    tie_created="$(printf '%s\n' "$containers_s" | awk -F'\t' '{print $5}' | sort | uniq -d)"
    tie_etime="$(printf '%s\n' "$clients_s" | awk -F'\t' '{print $3}' | sort | uniq -d)"
    ambiguous=false
    if [ "$n_containers" != "$n_clients" ] || [ -n "$tie_created" ] || [ -n "$tie_etime" ]; then
      ambiguous=true
    fi

    if [ "$cur_count" -gt 0 ] && [ "$ambiguous" = "true" ]; then
      # Ambiguity-safe over-protect: a current-session client exists for this
      # signature but the rank-bijection cannot be trusted — protect every
      # container of the signature rather than risk mis-pairing one away.
      local names
      names="$(printf '%s\n' "$containers_s" | awk -F'\t' '{print $2}')"
      protected="${protected}${names}
"
    else
      local tmpc tmpd cid cname cimg cproj ccreated cage dpid dppid detime dsig
      tmpc="$(mktemp)"; tmpd="$(mktemp)"
      printf '%s\n' "$containers_s" > "$tmpc"
      printf '%s\n' "$clients_s" > "$tmpd"
      while IFS=$'\t' read -r cid cname cimg cproj ccreated cage dpid dppid detime dsig; do
        [ -z "$cid" ] && continue
        if [ -n "${dppid:-}" ] && [ "$dppid" = "$cur_pid" ]; then
          protected="${protected}${cname}
"
        fi
      done < <(paste "$tmpc" "$tmpd")
      rm -f "$tmpc" "$tmpd"
    fi
  done <<< "$sigs"

  printf '%s' "$protected"
}

# _reap_emit_json — assemble + print the eidolons/mcp-reap.v1 object using
# the globals populated by the flow below. stdout only (called under --json).
_reap_emit_json() {
  local reap_arr protected_arr skipped_arr errors_arr claude_pid_json
  reap_arr="$(printf '%s' "$REAP_JSONL" | jq -s '[.[] | select(. != null)]')"
  protected_arr="$(printf '%s' "$PROTECTED_JSONL" | jq -s '[.[] | select(. != null)]')"
  skipped_arr="$(printf '%s' "$SKIPPED_JSONL" | jq -s '[.[] | select(. != null)]')"
  errors_arr="$(printf '%s' "$ERRORS_JSONL" | jq -s '[.[] | select(. != null)]')"
  claude_pid_json="null"
  [ -n "$CURRENT_CLAUDE_PID" ] && claude_pid_json="$CURRENT_CLAUDE_PID"

  jq -n \
    --arg schema "eidolons/mcp-reap.v1" \
    --arg project "$JSON_PROJECT_FIELD" \
    --argjson docker_available "$DOCKER_AVAILABLE" \
    --argjson executed "$EXECUTED" \
    --arg guard_status "$GUARD_STATUS" \
    --argjson claude_pid "$claude_pid_json" \
    --argjson protected_count "$PROTECTED_COUNT" \
    --argjson reap "$reap_arr" \
    --argjson protected "$protected_arr" \
    --argjson skipped "$skipped_arr" \
    --argjson errors "$errors_arr" \
    '{
      schema: $schema,
      project: $project,
      docker_available: $docker_available,
      executed: $executed,
      guard: { status: $guard_status, claude_pid: $claude_pid, protected_count: $protected_count },
      reap: $reap,
      protected: $protected,
      skipped: $skipped,
      errors: $errors
    }'
}

# _reap_print_summary — human-readable listing on stderr (never stdout —
# stdout is reserved for --json).
_reap_print_summary() {
  local n_reap n_protected n_skipped n_errors robj rname
  if [ "$DOCKER_AVAILABLE" = "false" ]; then
    info "reap: docker unavailable — nothing to reap"
    return 0
  fi

  n_reap="$(_reap_count_lines "$REAP_JSONL")"
  n_protected="$(_reap_count_lines "$PROTECTED_JSONL")"
  n_skipped="$(_reap_count_lines "$SKIPPED_JSONL")"
  n_errors="$(_reap_count_lines "$ERRORS_JSONL")"

  info "reap: guard status = ${GUARD_STATUS}"

  if [ "$n_reap" -eq 0 ]; then
    ok "reap: nothing to reap"
  elif [ "$EXECUTED" = "true" ]; then
    ok "reap: stopped ${n_reap} container(s)"
    while IFS= read -r robj; do
      [ -z "$robj" ] && continue
      rname="$(printf '%s' "$robj" | jq -r '.name')"
      info "  stopped: ${rname}"
    done <<< "$REAP_JSONL"
  else
    info "reap: would stop ${n_reap} container(s) (preview — pass --yes to execute)"
    while IFS= read -r robj; do
      [ -z "$robj" ] && continue
      rname="$(printf '%s' "$robj" | jq -r '.name')"
      info "  would stop: ${rname}"
    done <<< "$REAP_JSONL"
  fi

  [ "$n_protected" -gt 0 ] && info "reap: ${n_protected} container(s) protected (current session)"
  [ "$n_skipped" -gt 0 ] && info "reap: ${n_skipped} container(s) skipped (too young)"
  [ "$n_errors" -gt 0 ] && warn "reap: ${n_errors} container(s) failed to stop (non-fatal; already gone?)"
  return 0
}

# ─── Argument parsing ──────────────────────────────────────────────────────

DRY_RUN=false
YES=false
ALL=false
PROJECT_FLAG=""
OLDER_THAN_SECONDS=0
JSON=false

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -y|--yes)  YES=true; shift ;;
    --all)     ALL=true; shift ;;
    --project)
      [ -z "${2:-}" ] && { printf '%s\n' "--project requires an argument" >&2; exit 2; }
      PROJECT_FLAG="$2"
      shift 2
      ;;
    --older-than)
      [ -z "${2:-}" ] && { printf '%s\n' "--older-than requires an argument" >&2; exit 2; }
      if ! OLDER_THAN_SECONDS="$(_reap_dur_to_seconds "$2")"; then
        printf 'Malformed --older-than duration: %s (expected Ns|Nm|Nh|Nd)\n' "$2" >&2
        exit 2
      fi
      shift 2
      ;;
    --json) JSON=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [ "$ALL" = "true" ] && [ -n "$PROJECT_FLAG" ]; then
  printf '%s\n' "--all is mutually exclusive with --project" >&2
  exit 2
fi

EFFECTIVE_PROJECT="$PROJECT_FLAG"
if [ "$ALL" = "false" ] && [ -z "$EFFECTIVE_PROJECT" ]; then
  EFFECTIVE_PROJECT="$(project_slug)"
fi
JSON_PROJECT_FIELD="$EFFECTIVE_PROJECT"
[ "$ALL" = "true" ] && JSON_PROJECT_FIELD="*"

# ─── Result accumulators (defaults; overwritten below when docker is up) ──

DOCKER_AVAILABLE=false
EXECUTED=false
GUARD_STATUS="none"
CURRENT_CLAUDE_PID=""
PROTECTED_COUNT=0
REAP_JSONL=""
PROTECTED_JSONL=""
SKIPPED_JSONL=""
ERRORS_JSONL=""

# ─── Docker pre-flight (reused exactly as mcp_images.sh does) ─────────────

if atlas_aci_check_docker_cli 2>/dev/null && atlas_aci_check_docker_daemon 2>/dev/null; then
  DOCKER_AVAILABLE=true
else
  info "reap: docker unavailable — nothing to reap"
fi

if [ "$DOCKER_AVAILABLE" = "true" ]; then

  # ─── Candidate containers (label-only identity) ──────────────────────────
  DOCKER_PS_FMT=$'{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Label "eidolons.project"}}\t{{.CreatedAt}}'
  if [ "$ALL" = "true" ]; then
    DOCKER_PS_FILTER="label=eidolons.project"
  else
    DOCKER_PS_FILTER="label=eidolons.project=${EFFECTIVE_PROJECT}"
  fi
  CANDIDATES_RAW="$(docker ps --filter "$DOCKER_PS_FILTER" --format "$DOCKER_PS_FMT" 2>/dev/null || true)"

  # Enrich each candidate with its inspected Created + Config.Image.
  #
  # Created is used for BOTH the rank-bijection sort key — plain lexical ISO
  # comparison, no date math, so the P0 safety mechanism never depends on
  # date-parsing succeeding — and the --older-than age filter, whose failure
  # mode is fail-open-safe.
  #
  # Config.Image (NOT docker ps's own {{.Image}} column, verified live) is
  # the signature used for the guard's per-signature rank-bijection. `docker
  # ps --format {{.Image}}` prints a short form for a digest-run container
  # (e.g. "b3f67b4ef642") that never matches the FULL reference
  # ("ghcr.io/rynaro/atomos@sha256:b3f67b4ef642...") a `docker run` client's
  # process args actually carries — matching on the ps column would silently
  # never pair a container to its owning client, i.e. current-session
  # containers would never be marked PROTECTED. `docker inspect -f
  # '{{.Config.Image}}'` returns the exact reference passed to `docker run`,
  # which is what the client-side extraction (image@sha256:...) also reads
  # off the process args, so both sides compare byte-identical strings.
  DOCKER_INSPECT_FMT=$'{{.Created}}\t{{.Config.Image}}'
  NOW_EPOCH="$(date -u +%s)"
  CANDIDATES_ENRICHED=""
  while IFS=$'\t' read -r _cid _cname _cpsimg _cproj _cpscreated; do
    [ -z "$_cid" ] && continue
    _inspect_out="$(docker inspect -f "$DOCKER_INSPECT_FMT" "$_cid" 2>/dev/null || true)"
    _created="${_inspect_out%%$'\t'*}"
    _cfgimg=""
    case "$_inspect_out" in
      *$'\t'*) _cfgimg="${_inspect_out#*$'\t'}" ;;
    esac
    _cimg="$_cfgimg"
    [ -z "$_cimg" ] && _cimg="$_cpsimg"
    _age=""
    if [ -n "$_created" ]; then
      if _epoch="$(_reap_iso_to_epoch "$_created")"; then
        _age=$(( NOW_EPOCH - _epoch ))
      fi
    fi
    CANDIDATES_ENRICHED="${CANDIDATES_ENRICHED}${_cid}	${_cname}	${_cimg}	${_cproj}	${_created}	${_age}
"
  done <<< "$CANDIDATES_RAW"

  N_CANDIDATES="$(_reap_count_lines "$CANDIDATES_ENRICHED")"

  # ─── Current-session protection guard ────────────────────────────────────
  ALL_CLIENTS=""
  if [ -n "${CLAUDECODE:-}" ]; then
    if command -v ps >/dev/null 2>&1 && PS_SNAPSHOT="$(_reap_ps_snapshot 2>/dev/null)" && [ -n "$PS_SNAPSHOT" ]; then
      if CURRENT_CLAUDE_PID="$(_reap_resolve_claude_pid "$PS_SNAPSHOT")"; then
        ALL_CLIENTS="$(_reap_build_clients "$PS_SNAPSHOT")"
        CUR_CLIENT_COUNT="$(printf '%s\n' "$ALL_CLIENTS" | awk -F'\t' -v p="$CURRENT_CLAUDE_PID" '$2 == p' | awk 'END{print NR}')"
        if [ "$CUR_CLIENT_COUNT" -eq 0 ] && [ "$N_CANDIDATES" -gt 0 ]; then
          GUARD_STATUS="indeterminate"
        else
          GUARD_STATUS="active"
        fi
      else
        GUARD_STATUS="indeterminate"
      fi
    else
      GUARD_STATUS="indeterminate"
    fi
  fi

  PROTECTED_NAMES=""
  case "$GUARD_STATUS" in
    indeterminate)
      PROTECTED_NAMES="$(printf '%s\n' "$CANDIDATES_ENRICHED" | awk -F'\t' '$1 != "" {print $2}')"
      warn "reap: session guard indeterminate — protecting every candidate, stopping nothing"
      ;;
    active)
      PROTECTED_NAMES="$(_reap_compute_protected "$CANDIDATES_ENRICHED" "$ALL_CLIENTS" "$CURRENT_CLAUDE_PID")"
      ;;
    none) : ;;
  esac

  # ─── Classify each candidate: protected | skipped (too-young) | reap ────
  while IFS=$'\t' read -r _cid _cname _cimg _cproj _ccreated _cage; do
    [ -z "$_cid" ] && continue

    _age_json="null"
    [ -n "$_cage" ] && _age_json="$_cage"

    # NOTE: -c (compact) is load-bearing here, not cosmetic. Every one of
    # these accumulators is later walked with `while read -r line`, which is
    # line-based; a pretty-printed (multi-line) jq object would silently
    # fragment across iterations (and, in the docker-stop loop below, that
    # fragmentation would corrupt which containers actually get stopped).
    if _reap_name_in_list "$_cname" "$PROTECTED_NAMES"; then
      _obj="$(jq -nc --arg id "$_cid" --arg name "$_cname" --arg image "$_cimg" --arg project "$_cproj" --argjson age "$_age_json" \
        '{id:$id, name:$name, image:$image, project:$project, age_seconds:$age}')"
      PROTECTED_JSONL="${PROTECTED_JSONL}${_obj}
"
      continue
    fi

    if [ -z "$_cage" ] || [ "$_cage" -lt "$OLDER_THAN_SECONDS" ]; then
      _obj="$(jq -nc --arg id "$_cid" --arg name "$_cname" --arg reason "too-young" \
        '{id:$id, name:$name, reason:$reason}')"
      SKIPPED_JSONL="${SKIPPED_JSONL}${_obj}
"
      continue
    fi

    _obj="$(jq -nc --arg id "$_cid" --arg name "$_cname" --arg image "$_cimg" --arg project "$_cproj" --argjson age "$_age_json" \
      '{id:$id, name:$name, image:$image, project:$project, age_seconds:$age, stopped:false}')"
    REAP_JSONL="${REAP_JSONL}${_obj}
"
  done <<< "$CANDIDATES_ENRICHED"

  PROTECTED_COUNT="$(_reap_count_lines "$PROTECTED_JSONL")"

  # ─── Execute (only --yes without --dry-run) ──────────────────────────────
  if [ "$YES" = "true" ] && [ "$DRY_RUN" = "false" ] && [ "$(_reap_count_lines "$REAP_JSONL")" -gt 0 ]; then
    EXECUTED=true
    _new_reap_jsonl=""
    while IFS= read -r _robj; do
      [ -z "$_robj" ] && continue
      _rid="$(printf '%s' "$_robj" | jq -r '.id')"
      _rname="$(printf '%s' "$_robj" | jq -r '.name')"
      if docker stop "$_rname" >/dev/null 2>&1; then
        _robj="$(printf '%s' "$_robj" | jq -c '.stopped = true')"
      else
        _err_obj="$(jq -nc --arg id "$_rid" --arg msg "docker stop failed for ${_rname} (already removed?)" \
          '{id:$id, message:$msg}')"
        ERRORS_JSONL="${ERRORS_JSONL}${_err_obj}
"
      fi
      _new_reap_jsonl="${_new_reap_jsonl}${_robj}
"
    done <<< "$REAP_JSONL"
    REAP_JSONL="$_new_reap_jsonl"
  elif [ "$YES" = "true" ] && [ "$DRY_RUN" = "true" ]; then
    info "reap: --dry-run overrides --yes — preview only"
  fi
fi

# ─── Emit ───────────────────────────────────────────────────────────────────

_reap_print_summary

if [ "$JSON" = "true" ]; then
  _reap_emit_json
fi

exit 0
