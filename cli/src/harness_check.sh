#!/usr/bin/env bash
# Validate installed hook files and the host registrations that load them.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf '%s\n' 'Usage: eidolons harness check [--smoke --host codex]' \
    'Checks lock-to-file registration, executable bits, and shell syntax.' \
    '--smoke runs local SessionStart and UserPromptSubmit shims without a model call.'
  exit 0
fi
SMOKE=false
SMOKE_HOST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke) SMOKE=true; shift ;;
    --host) SMOKE_HOST="${2:-}"; shift 2 ;;
    *) die "Unknown option: $1" ;;
  esac
done
if [[ "$SMOKE" == "true" ]]; then
  [[ "$SMOKE_HOST" == "codex" ]] || die "Local smoke currently supports --host codex"
elif [[ -n "$SMOKE_HOST" ]]; then
  die "--host requires --smoke"
fi
[[ -f "$PROJECT_LOCK" ]] || die "No eidolons.lock found. Run 'eidolons sync' first."

lock_json="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null)" || die "Cannot parse eidolons.lock"
schema="$(printf '%s' "$lock_json" | jq -r '.harness.schema_version // empty')"
[[ -n "$schema" ]] || die "Harness is not installed. Run 'eidolons harness install'."

failures=0
while IFS= read -r shim; do
  [[ -n "$shim" ]] || continue
  if [[ ! -f "$shim" || ! -x "$shim" ]]; then
    printf 'FAIL missing or non-executable hook: %s\n' "$shim" >&2
    failures=$((failures + 1))
    continue
  fi
  if ! bash -n "$shim"; then
    printf 'FAIL invalid hook syntax: %s\n' "$shim" >&2
    failures=$((failures + 1))
  fi
  case "$shim" in
    *claude-code*) surface=".claude/settings.json" ;;
    *codex*)       surface=".codex/hooks.json" ;;
    *copilot*)     surface=".github/hooks/eidolons.json" ;;
    *)             surface="" ;;
  esac
  if [[ -n "$surface" ]]; then
    if [[ ! -f "$surface" ]] || ! jq -e --arg p "$shim" \
      '[.hooks // {} | .. | strings] | any(contains($p))' "$surface" >/dev/null 2>&1; then
      # Claude commands are rooted through CLAUDE_PROJECT_DIR and therefore
      # contain only the stable suffix, not the lock's relative spelling.
      suffix="$(basename "$shim")"
      if [[ ! -f "$surface" ]] || ! jq -e --arg p "$suffix" \
        '[.hooks // {} | .. | strings] | any(contains($p))' "$surface" >/dev/null 2>&1; then
        printf 'FAIL hook is not registered in %s: %s\n' "$surface" "$shim" >&2
        failures=$((failures + 1))
      fi
    fi
  fi
done <<EOF
$(printf '%s' "$lock_json" | jq -r '(.harness.shim_paths // [])[]')
EOF

if (( failures > 0 )); then
  printf 'harness check: %d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'harness check: ok (schema %s)\n' "$schema"
if [[ "$SMOKE" == "true" ]]; then
  # A local qualification check only: project trust, hook hash approval, and
  # actual runtime firing cannot be proved by calling a shim directly.
  shim_dir=".eidolons/harness/hooks"
  [[ -x "$shim_dir/codex-SessionStart.sh" && -x "$shim_dir/codex-UserPromptSubmit.sh" ]] || \
    die "Codex routing shims are missing"
  cli_path="$(cd "$SELF_DIR/.." && pwd)"
  smoke_session="$(PATH="$cli_path:$PATH" bash "$shim_dir/codex-SessionStart.sh" 2>/dev/null)" || \
    die "Codex SessionStart local smoke failed"
  printf '%s' "$smoke_session" | jq -e \
    '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | type == "string" and length > 0)' \
    >/dev/null 2>&1 || die "Codex SessionStart local smoke produced no routing context"
  smoke_prompt='{"prompt":"ATLAS, map the parser"}'
  smoke_route="$(printf '%s' "$smoke_prompt" | PATH="$cli_path:$PATH" bash "$shim_dir/codex-UserPromptSubmit.sh" 2>/dev/null)" || \
    die "Codex UserPromptSubmit local smoke failed"
  printf '%s' "$smoke_route" | jq -e \
    '.hookSpecificOutput.hookEventName == "UserPromptSubmit" and (.hookSpecificOutput.additionalContext | type == "string" and length > 0)' \
    >/dev/null 2>&1 || die "Codex UserPromptSubmit local smoke produced no routing context"
  printf 'harness local smoke: ok (codex SessionStart + UserPromptSubmit; no model call)\n'
  printf 'codex runtime qualification: unknown (project trust and hook hash approval required)\n'
fi
