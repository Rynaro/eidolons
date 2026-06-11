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
# PREFLIGHT
# ═══════════════════════════════════════════════════════════════════════════

# Defaults (overridable by env).
QUERY_OVERRIDE=""
TTL="${EIDOLONS_MEMORY_PREFLIGHT_TTL:-900}"
NO_CACHE=0
TIMEOUT="${EIDOLONS_MEMORY_PREFLIGHT_TIMEOUT:-8}"

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
    -h|--help)
      cat <<'EOF'
eidolons memory preflight — bounded one-shot crystalium recall

Usage: eidolons memory preflight [options]

Options:
  --query <s>       Recall query (default: 'project <slug> recent context')
  --ttl <sec>       Cache TTL in seconds (default: 900 / EIDOLONS_MEMORY_PREFLIGHT_TTL)
  --no-cache        Bypass cache read and write
  --timeout <sec>   Docker kill timeout in seconds (default: 8 / EIDOLONS_MEMORY_PREFLIGHT_TIMEOUT)

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

if [ ! -f "$PROJECT_ROOT/.mcp.json" ]; then
  info "memory preflight: .mcp.json absent — skipping"
  exit 0
fi

# ── Step 2: Crystalium-present gate ───────────────────────────────────────
# Gate A: .mcp.json must have mcpServers.crystalium
if ! jq -e '.mcpServers.crystalium' "$PROJECT_ROOT/.mcp.json" >/dev/null 2>&1; then
  info "memory preflight: crystalium not in .mcp.json — skipping"
  exit 0
fi

# Gate B: eidolons.mcp.lock must have a crystalium entry.
if [ ! -f "$PROJECT_ROOT/eidolons.mcp.lock" ] \
   || ! grep -q "name: crystalium" "$PROJECT_ROOT/eidolons.mcp.lock" 2>/dev/null; then
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

_docker_script="$(mktemp)"
# shellcheck disable=SC2064
trap 'rm -f "$_docker_script"' EXIT

# Write the script header.
# Use the command from .mcp.json (typically "docker"); args already begin with "run".
_docker_cmd="$(jq -r '.mcpServers.crystalium.command // "docker"' "$PROJECT_ROOT/.mcp.json" 2>/dev/null)"
: "${_docker_cmd:=docker}"
printf '#!/usr/bin/env bash\nexec %s' "$_docker_cmd" > "$_docker_script"

# Use jq to output each arg on its own line and process with a state machine.
_skip_next=0
_appended_recall=0
while IFS= read -r _arg; do
  if [ "$_skip_next" -eq 1 ]; then
    _skip_next=0
    continue
  fi
  # Strip interactive flag.
  if [ "$_arg" = "-i" ]; then
    continue
  fi
  # Strip --name flag; mark next token (the value) for skip.
  if [ "$_arg" = "--name" ]; then
    _skip_next=1
    continue
  fi
  # Replace "serve" with recall subcommand + flags.
  if [ "$_arg" = "serve" ] && [ "$_appended_recall" -eq 0 ]; then
    _appended_recall=1
    # Append recall subcommand with properly quoted args.
    # Use printf %q for safe quoting if available, else single-quote.
    _q_query="$(printf '%q' "$_query" 2>/dev/null || printf "'%s'" "$_query")"
    _q_slug="$(printf '%q' "$_project_slug" 2>/dev/null || printf "'%s'" "$_project_slug")"
    printf ' recall --query %s --scope-project %s --k 5 --format json' \
      "$_q_query" "$_q_slug" >> "$_docker_script"
    continue
  fi
  # Append this arg (shell-quoted).
  _q_arg="$(printf '%q' "$_arg" 2>/dev/null || printf "'%s'" "$_arg")"
  printf ' %s' "$_q_arg" >> "$_docker_script"
done < <(jq -r '.mcpServers.crystalium.args[]' "$PROJECT_ROOT/.mcp.json" 2>/dev/null)

printf '\n' >> "$_docker_script"
chmod +x "$_docker_script"

if [ "$_appended_recall" -eq 0 ]; then
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

_digest="$(printf '%s' "$_docker_out" \
  | jq -r '.records[]? | "[" + .layer + "/" + .trust_tier + "] " + .summary' 2>/dev/null \
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
