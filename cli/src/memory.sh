#!/usr/bin/env bash
# cli/src/memory.sh — 'eidolons memory' sub-dispatcher
# ═══════════════════════════════════════════════════════════════════════════
#
# Implements: R27 — eidolons memory preflight
#
# Sub-commands:
#   preflight [--query <s>] [--ttl <sec>] [--no-cache] [--timeout <sec>]
#
# Stdout contract (memory preflight):
#   stdout IS the digest and nothing else.
#   On any failure / absent crystalium / absent docker: empty stdout, exit 0.
#
# Bash 3.2 safe: no declare -A, no ${var,,}, no readarray, no &>>.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_memory_probe.sh"

_sub="${1:-}"
[ $# -gt 0 ] && shift

# ── usage ──────────────────────────────────────────────────────────────────
_memory_usage() {
  cat <<'EOF'
eidolons memory — mechanical memory pre-flight (GAP-2)

Usage: eidolons memory <subcommand> [options]

Subcommands:
  preflight   Run a bounded one-shot crystalium recall and emit a compact
              injectable digest. Used by the SessionStart harness arm.

              Options:
                --query <s>       Recall query (default: 'project <slug> recent context')
                --ttl <sec>       Cache TTL in seconds (default: 900)
                                  Env: EIDOLONS_MEMORY_PREFLIGHT_TTL
                --no-cache        Bypass cache read and write (always run live)
                --timeout <sec>   Docker kill timeout in seconds (default: 8)
                                  Env: EIDOLONS_MEMORY_PREFLIGHT_TIMEOUT
                --explain         Human diagnostic report instead of the digest
                                  (gate/cache/invocation/exit-code/records/tokens).
                                  Never writes the TTL cache. Exit: always 0.

              Stdout: [layer/tier] summary digest, <=1500 chars, or empty on failure.
              Exit:   always 0.

              Gate: crystalium must be present in .mcp.json AND eidolons.mcp.lock.
              Absent -> empty stdout, exit 0.

Run 'eidolons memory preflight --help' for preflight-specific usage.
EOF
}

case "$_sub" in
  preflight) ;;
  -h|--help|help|"") _memory_usage; exit 0 ;;
  *)
    printf 'Unknown memory subcommand: %s\n' "$_sub" >&2
    printf 'Available: preflight\n' >&2
    exit 2
    ;;
esac

# ═══════════════════════════════════════════════════════════════════════════
# EXPLAIN — human diagnostic report (GAP: silent-empty-recall incident)
# ═══════════════════════════════════════════════════════════════════════════
# Real incident that motivated this: the live store returned zero records for
# every query while containing 9 crystals — silently, because the digest path
# treats "zero records" identically to "gate absent" / "docker missing" (all
# collapse to empty stdout, by design — the digest is injected into hook
# context and must never explain itself there). Operators had no way to tell
# "store is empty/mis-scoped" apart from "crystalium isn't wired here at all".
#
# _memory_preflight_explain prints a full report to stdout instead of the
# digest: gate status, cache status (informational only), the resolved docker
# invocation (nothing redacted — it's local), the recall's exit code, record
# count, total_tokens, and the scope/layers used. It ALWAYS performs a live
# recall (bypassing any cache hit) so the report reflects the store's real,
# current state, and it NEVER writes the TTL cache — a diagnostic run must
# not mask the next real preflight's cache miss (or manufacture a false hit).
#
# This is deliberately independent of the digest-path Steps below: --explain
# is gated (and returns) before Step 1 runs, so the non-explain digest path
# is untouched by this function's existence.
_memory_preflight_explain() {
  local project_root="$1"

  printf 'eidolons memory preflight --explain\n'
  printf '═══════════════════════════════════════════════════════════════\n'

  # ── Gate status ────────────────────────────────────────────────────────
  local mcp_gate="FAIL" lock_gate="FAIL"
  if memory_probe_mcp_gate "$project_root"; then mcp_gate="PASS"; fi
  if memory_probe_lock_gate "$project_root"; then lock_gate="PASS"; fi

  printf 'Gate:\n'
  printf '  .mcp.json has mcpServers.crystalium     %s\n' "$mcp_gate"
  printf '  eidolons.mcp.lock has crystalium entry  %s\n' "$lock_gate"

  if [ "$mcp_gate" != "PASS" ] || [ "$lock_gate" != "PASS" ]; then
    printf '\nResult: crystalium is not gated in — a normal preflight run would emit empty stdout, exit 0.\n'
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    printf '\nResult: docker not on PATH — a normal preflight run would emit empty stdout, exit 0.\n'
    return 0
  fi

  # ── Resolve query/slug (mirrors the digest path's Step 4) ────────────────
  local slug query
  slug="$(memory_probe_project_slug "$project_root")"
  if [ -n "$QUERY_OVERRIDE" ]; then
    query="$QUERY_OVERRIDE"
  else
    query="project ${slug} recent context"
  fi

  # ── Cache status (informational only — --explain never reads-to-shortcut
  # and never writes; see the function docstring above) ─────────────────────
  local cache_file="$project_root/.eidolons/harness/cache/preflight.json"
  printf '\nCache:\n'
  printf '  file    %s\n' "$cache_file"
  if [ -f "$cache_file" ]; then
    local now cached_at cached_query age
    now="$(date +%s 2>/dev/null || echo "0")"
    cached_at="$(jq -r '.cached_at // 0' "$cache_file" 2>/dev/null || echo "0")"
    cached_query="$(jq -r '.query // ""' "$cache_file" 2>/dev/null || echo "")"
    age=$(( now - cached_at ))
    printf '  age     %ss (TTL %ss)\n' "$age" "$TTL"
    if [ "$age" -lt "$TTL" ] && [ "$cached_query" = "$query" ]; then
      printf '  status  HIT — a normal preflight run would reuse this digest. --explain always runs live regardless.\n'
    else
      printf '  status  MISS (stale or query mismatch)\n'
    fi
  else
    printf '  status  MISS (no cache file yet)\n'
  fi

  # ── Build + print the resolved docker invocation ──────────────────────────
  local script q_query q_slug recall_args
  script="$(mktemp)"
  q_query="$(memory_probe_quote "$query")"
  q_slug="$(memory_probe_quote "$slug")"
  recall_args="recall --query $q_query --scope-project $q_slug --k 5 --format json --layers semantic,episodic,procedural"

  printf '\nResolved invocation:\n'
  if ! memory_probe_build_docker_script "$project_root" "$recall_args" "$script"; then
    printf "  'serve' not found in .mcp.json crystalium args — cannot build an invocation.\n"
    rm -f "$script"
    return 0
  fi
  # Print the resolved command line (the script's 2nd line, after the shebang).
  # Nothing is redacted — this only ever runs locally.
  tail -n +2 "$script"

  # ── Run live (never cached) ────────────────────────────────────────────────
  local tmpout docker_exit=0
  tmpout="$(mktemp)"
  if command -v timeout >/dev/null 2>&1; then
    timeout "${TIMEOUT}s" bash "$script" > "$tmpout" 2>/dev/null || docker_exit=$?
  else
    bash "$script" > "$tmpout" 2>/dev/null &
    local docker_pid=$!
    ( sleep "$TIMEOUT" 2>/dev/null; kill -TERM "$docker_pid" 2>/dev/null ) &
    local watcher_pid=$!
    wait "$docker_pid" 2>/dev/null || docker_exit=$?
    kill "$watcher_pid" 2>/dev/null || true
    wait "$watcher_pid" 2>/dev/null || true
  fi
  rm -f "$script"

  local docker_out
  docker_out="$(cat "$tmpout" 2>/dev/null || echo "")"
  rm -f "$tmpout"

  printf '\nRecall:\n'
  printf '  exit code      %s\n' "$docker_exit"

  if [ "$docker_exit" -ne 0 ]; then
    printf '  result         docker failed or timed out — no output to parse.\n'
    return 0
  fi

  if [ -z "$docker_out" ]; then
    printf '  result         empty stdout from docker.\n'
    return 0
  fi

  if ! printf '%s' "$docker_out" | jq empty >/dev/null 2>&1; then
    printf '  result         malformed JSON from docker.\n'
    printf '  raw output     %s\n' "$docker_out"
    return 0
  fi

  local count tokens slots
  count="$(printf '%s' "$docker_out" | jq -r '(.records // []) | length' 2>/dev/null || echo "0")"
  tokens="$(printf '%s' "$docker_out" | jq -r '.total_tokens // 0' 2>/dev/null || echo "0")"
  slots="$(printf '%s' "$docker_out" | jq -c '.slot_breakdown // {}' 2>/dev/null || echo "{}")"

  printf '  records        %s\n' "$count"
  printf '  total_tokens   %s\n' "$tokens"
  printf '  slot_breakdown %s\n' "$slots"
  printf '  scope.project  %s\n' "$slug"
  printf '  layers         semantic,episodic,procedural (explicit; execution excluded — not a session-start artifact)\n'

  if [ "$count" -eq 0 ]; then
    printf '\n0 records returned — store may be empty, mis-scoped, or filtered (status/scope); see crystalium recall defaults (active-only).\n'
  fi

  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PREFLIGHT
# ═══════════════════════════════════════════════════════════════════════════

# Defaults (overridable by env).
QUERY_OVERRIDE=""
TTL="${EIDOLONS_MEMORY_PREFLIGHT_TTL:-900}"
NO_CACHE=0
TIMEOUT="${EIDOLONS_MEMORY_PREFLIGHT_TIMEOUT:-8}"
EXPLAIN=0

# Parse preflight flags.
while [ $# -gt 0 ]; do
  case "$1" in
    --query)     QUERY_OVERRIDE="$2"; shift 2 ;;
    --query=*)   QUERY_OVERRIDE="${1#--query=}"; shift ;;
    --ttl)       TTL="$2"; shift 2 ;;
    --ttl=*)     TTL="${1#--ttl=}"; shift ;;
    --no-cache)  NO_CACHE=1; shift ;;
    --timeout)   TIMEOUT="$2"; shift 2 ;;
    --timeout=*) TIMEOUT="${1#--timeout=}"; shift ;;
    --explain)   EXPLAIN=1; shift ;;
    -h|--help)
      cat <<'EOF'
eidolons memory preflight — bounded one-shot crystalium recall

Usage: eidolons memory preflight [options]

Options:
  --query <s>       Recall query (default: 'project <slug> recent context')
  --ttl <sec>       Cache TTL in seconds (default: 900 / EIDOLONS_MEMORY_PREFLIGHT_TTL)
  --no-cache        Bypass cache read and write
  --timeout <sec>   Docker kill timeout in seconds (default: 8 / EIDOLONS_MEMORY_PREFLIGHT_TIMEOUT)
  --explain         Human diagnostic report (gate/cache/invocation/exit-code/
                     records/total_tokens) instead of the injectable digest.
                     Never writes the TTL cache. Exit: always 0.

Stdout:  [layer/tier] summary digest, <=1500 chars; or empty on any failure.
Exit:    always 0.

The digest is derived from .mcp.json's crystalium args — the same volume,
env, image digest, and security flags as the running serve container, but
replacing 'serve' with 'python -m crystalium recall ... --format json'.
Results are TTL-cached at .eidolons/harness/cache/preflight.json.
EOF
      exit 0
      ;;
    *) printf 'Unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ── Step 1: Check .mcp.json exists ────────────────────────────────────────
PROJECT_ROOT="$(pwd)"

# ── --explain: human diagnostic report, fully separate from the digest path.
# Guarded here (before any of the digest-path Steps run) so the default
# (non-explain) behavior below is untouched — byte-identical to before this
# flag existed. See _memory_preflight_explain for the report contents.
if [ "$EXPLAIN" -eq 1 ]; then
  _memory_preflight_explain "$PROJECT_ROOT"
  exit 0
fi

if [ ! -f "$PROJECT_ROOT/.mcp.json" ]; then
  info "memory preflight: .mcp.json absent — skipping"
  exit 0
fi

# ── Step 2: Crystalium-present gate ───────────────────────────────────────
# Gate A: .mcp.json must have mcpServers.crystalium
if ! memory_probe_mcp_gate "$PROJECT_ROOT"; then
  info "memory preflight: crystalium not in .mcp.json — skipping"
  exit 0
fi

# Gate B: eidolons.mcp.lock must have a crystalium entry.
if ! memory_probe_lock_gate "$PROJECT_ROOT"; then
  info "memory preflight: crystalium not in eidolons.mcp.lock — skipping"
  exit 0
fi

# ── Step 3: Docker availability ───────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  info "memory preflight: docker not on PATH — skipping"
  exit 0
fi

# ── Step 4: Compute slug + default query (deterministic) ──────────────────
_basename="$(basename "$PROJECT_ROOT")"
_project_slug="$(printf '%s' "$_basename" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs 'a-z0-9' '-' \
  | sed -e 's|^-||' -e 's|-$||')"

if [ -n "$QUERY_OVERRIDE" ]; then
  _query="$QUERY_OVERRIDE"
else
  _query="project ${_project_slug} recent context"
fi

# ── Step 5: Cache check ────────────────────────────────────────────────────
CACHE_FILE="$PROJECT_ROOT/.eidolons/harness/cache/preflight.json"

if [ "$NO_CACHE" -eq 0 ] && [ -f "$CACHE_FILE" ]; then
  _now="$(date +%s 2>/dev/null || echo "0")"
  _cached_at="$(jq -r '.cached_at // 0' "$CACHE_FILE" 2>/dev/null || echo "0")"
  _cached_query="$(jq -r '.query // ""' "$CACHE_FILE" 2>/dev/null || echo "")"
  _age=$(( _now - _cached_at ))
  if [ "$_age" -lt "$TTL" ] && [ "$_cached_query" = "$_query" ]; then
    # Cache HIT — print digest and exit.
    _cached_digest="$(jq -r '.digest // ""' "$CACHE_FILE" 2>/dev/null || echo "")"
    if [ -n "$_cached_digest" ]; then
      printf '%s' "$_cached_digest"
      exit 0
    fi
    # empty cached digest → fall through to live run
  fi
fi

# ── Step 6: Build recall args from .mcp.json ──────────────────────────────
# Transform the crystalium serve args to a recall invocation:
#   - Strip "-i" (interactive stdin flag — one-shot needs no stdin)
#   - Strip "--name <value>" pair (avoid colliding with running serve container)
#   - Replace trailing "serve" token with recall subcommand
#
# We build a shell-exec wrapper: a temporary script that calls docker run
# with the exact transformed args. This avoids eval and arrays (bash 3.2 safe).
# The transform itself lives in lib_memory_probe.sh (shared with doctor D13
# and canary --memory) — this call site only supplies the recall-specific
# replacement string.

_docker_script="$(mktemp)"
# shellcheck disable=SC2064
trap 'rm -f "$_docker_script"' EXIT

_q_query="$(memory_probe_quote "$_query")"
_q_slug="$(memory_probe_quote "$_project_slug")"
# --layers explicitly includes procedural (skills) alongside semantic/episodic
# so a weak orchestrator can spot reusable verified procedures at session
# start (Step 8 renders procedural records with a '[skill/...]' prefix).
# execution is excluded — plan-checkpoint state isn't a session-start digest
# concern.
_recall_args="recall --query $_q_query --scope-project $_q_slug --k 5 --format json --layers semantic,episodic,procedural"

if ! memory_probe_build_docker_script "$PROJECT_ROOT" "$_recall_args" "$_docker_script"; then
  info "memory preflight: 'serve' not found in crystalium args — skipping"
  exit 0
fi

# ── Digest cross-check (defense-in-depth, AC-R27-10) ─────────────────────
_mcp_image_ref="$(jq -r '.mcpServers.crystalium.args[]' "$PROJECT_ROOT/.mcp.json" 2>/dev/null \
  | grep -E '^ghcr\.' | head -1 || echo "")"
_lock_digest=""
if [ -f "$PROJECT_ROOT/eidolons.mcp.lock" ]; then
  _lock_digest="$(awk '/name: crystalium/{found=1} found && /value:/{print $2; exit}' \
    "$PROJECT_ROOT/eidolons.mcp.lock" 2>/dev/null | tr -d '"' || echo "")"
fi
if [ -n "$_lock_digest" ] && [ -n "$_mcp_image_ref" ]; then
  if ! printf '%s' "$_mcp_image_ref" | grep -qF "$_lock_digest"; then
    info "memory preflight: .mcp.json image digest does not match eidolons.mcp.lock — proceeding with .mcp.json"
  fi
fi

# ── Step 7: Run with timeout (bash 3.2 portable) ─────────────────────────
# Prefer coreutils timeout(1); fall back to background-watcher idiom.
_tmpout="$(mktemp)"
_docker_exit=0

if command -v timeout >/dev/null 2>&1; then
  timeout "${TIMEOUT}s" bash "$_docker_script" > "$_tmpout" 2>/dev/null || _docker_exit=$?
else
  # bash-3.2 background-watcher idiom (no timeout binary).
  bash "$_docker_script" > "$_tmpout" 2>/dev/null &
  _docker_pid=$!
  ( sleep "$TIMEOUT" 2>/dev/null; kill -TERM "$_docker_pid" 2>/dev/null ) &
  _watcher_pid=$!
  wait "$_docker_pid" 2>/dev/null || _docker_exit=$?
  kill "$_watcher_pid" 2>/dev/null || true
  wait "$_watcher_pid" 2>/dev/null || true
fi

if [ "$_docker_exit" -ne 0 ]; then
  info "memory preflight: docker recall failed or timed out (exit $_docker_exit) — skipping"
  rm -f "$_tmpout"
  exit 0
fi

_docker_out="$(cat "$_tmpout" 2>/dev/null || echo "")"
rm -f "$_tmpout"

if [ -z "$_docker_out" ]; then
  info "memory preflight: docker returned empty output — skipping"
  exit 0
fi

# ── Step 8: Transform RecallResult JSON → digest ─────────────────────────
# Validate JSON first (AC-R27-4: malformed JSON → empty stdout exit 0).
if ! printf '%s' "$_docker_out" | jq empty >/dev/null 2>&1; then
  info "memory preflight: docker returned malformed JSON — skipping"
  exit 0
fi

# Procedural-layer records render with a '[skill/tier]' prefix (instead of
# '[procedural/tier]') so a verified reusable procedure stands out from plain
# recall context — see the harness_hook.sh SessionStart hint that tells the
# host to prefer invoking a '[skill/...]' line over re-deriving the procedure.
_digest="$(printf '%s' "$_docker_out" \
  | jq -r '.records[]? | "[" + (if .layer == "procedural" then "skill" else .layer end) + "/" + .trust_tier + "] " + .summary' 2>/dev/null \
  | head -c 1500 || true)"

if [ -z "$_digest" ]; then
  info "memory preflight: no records in recall result — skipping"
  exit 0
fi

# ── Step 9: Cache write ────────────────────────────────────────────────────
if [ "$NO_CACHE" -eq 0 ]; then
  _cache_dir="$(dirname "$CACHE_FILE")"
  mkdir -p "$_cache_dir" 2>/dev/null || true
  _now_write="$(date +%s 2>/dev/null || echo "0")"
  _digest_json="$(printf '%s' "$_digest" | jq -Rs '.' 2>/dev/null || printf '""')"
  _query_json="$(printf '%s' "$_query" | jq -Rs '.' 2>/dev/null || printf '""')"
  printf '{"cached_at":%s,"query":%s,"digest":%s}\n' \
    "$_now_write" "$_query_json" "$_digest_json" > "$CACHE_FILE" 2>/dev/null || true
fi

# ── Step 10: Print digest to stdout ───────────────────────────────────────
printf '%s' "$_digest"
exit 0
