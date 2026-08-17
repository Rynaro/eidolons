#!/usr/bin/env bash
# Validate installed hook files and the host registrations that load them.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf '%s\n' 'Usage: eidolons harness check' \
    'Checks lock-to-file registration, executable bits, and shell syntax.'
  exit 0
fi
[[ $# -eq 0 ]] || die "Unknown option: $1"
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
