#!/usr/bin/env bash
# eidolons doctor — health-check installed Eidolons and host wiring
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<EOF
eidolons doctor — health-check installed Eidolons and host wiring

Usage: eidolons doctor [OPTIONS]

Options:
  --fix         Attempt to auto-repair simple issues (missing symlinks, lockfile drift)
  -h, --help    Show this help

Checks:
  - eidolons.yaml present and valid
  - eidolons.lock present and consistent with manifest
  - Each installed Eidolon has its files in .eidolons/<n>/
  - Each installed Eidolon's install.manifest.json is valid
  - Host dispatch files exist for every host listed in eidolons.yaml
  - Release-integrity status per lock entry (verified / legacy / missing)
EOF
}

FIX=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)    FIX=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)        echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

ERRORS=0
err() { ERRORS=$((ERRORS + 1)); printf "  %s✗%s %s\n" "$RED" "$RESET" "$*"; }
pass() { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$*"; }

say "eidolons doctor — checking $(pwd)"
echo ""

# ─── Check 1: manifest + lock ────────────────────────────────────────────
ui_section_out "Manifest + lock"
if [[ -f "$PROJECT_MANIFEST" ]]; then
  pass "eidolons.yaml present"
else
  err "eidolons.yaml missing — run 'eidolons init'"
  exit 1
fi

if [[ -f "$PROJECT_LOCK" ]]; then
  pass "eidolons.lock present"
else
  err "eidolons.lock missing — run 'eidolons sync'"
fi

# ─── Check 2: per-member installs ───────────────────────────────────────
ui_section_out "Installed members"
CLAUDE_WIRED=false
if yaml_to_json "$PROJECT_MANIFEST" | jq -e '.hosts.wire | index("claude-code")' >/dev/null 2>&1; then
  CLAUDE_WIRED=true
fi
manifest_members | while read -r name; do
  target="./.eidolons/$name"
  if [[ ! -d "$target" ]]; then
    err "$name declared but not installed at $target (per-Eidolon install.sh didn't run or failed)"
    continue
  fi
  if [[ ! -f "$target/install.manifest.json" ]]; then
    err "$name installed at $target but install.manifest.json is missing (not EIIS-conformant — report upstream)"
  elif ! jq -e . "$target/install.manifest.json" >/dev/null 2>&1; then
    err "$name has corrupt install.manifest.json at $target/install.manifest.json"
  else
    pass "$name installed with valid manifest"
  fi
  if [[ "$CLAUDE_WIRED" == "true" ]] && [[ ! -f ".claude/agents/$name.md" ]]; then
    err "$name installed but .claude/agents/$name.md missing (per-Eidolon installer didn't wire claude-code)"
  fi
done

# Read shared_dispatch preference — defaults to false when the key is absent.
SHARED_DISPATCH="$(yaml_to_json "$PROJECT_MANIFEST" | jq -r '.hosts.shared_dispatch // false')"

# ─── Check 3: host wiring ───────────────────────────────────────────────
ui_section_out "Host wiring"
hosts="$(yaml_to_json "$PROJECT_MANIFEST" | jq -r '.hosts.wire[]')"
for host in $hosts; do
  case "$host" in
    claude-code)
      # Per-vendor self-sufficient files live under .claude/agents/ and .claude/skills/.
      # Root CLAUDE.md is only required when shared_dispatch is opted in.
      if [[ -d ".claude/agents" ]] && ls .claude/agents/*.md >/dev/null 2>&1; then
        pass "claude-code wired (.claude/agents/*.md present)"
      elif [[ "$SHARED_DISPATCH" == "true" && -f "CLAUDE.md" ]]; then
        pass "claude-code wired (CLAUDE.md shared dispatch)"
      else
        err "claude-code declared but no .claude/agents/*.md found"
      fi
      ;;
    copilot)
      # Per-vendor files: .github/instructions/<eidolon>-<skill>.instructions.md
      if [[ -d ".github/instructions" ]] && ls .github/instructions/*.instructions.md >/dev/null 2>&1; then
        pass "copilot wired (.github/instructions/*.instructions.md present)"
      elif [[ "$SHARED_DISPATCH" == "true" ]] && [[ -f ".github/copilot-instructions.md" || -f "AGENTS.md" ]]; then
        pass "copilot wired (shared dispatch)"
      else
        err "copilot declared but no .github/instructions/ content found"
      fi
      ;;
    cursor)
      if [[ -d ".cursor/rules" ]] && ls .cursor/rules/*.mdc >/dev/null 2>&1; then
        pass "cursor wired (.cursor/rules/*.mdc present)"
      elif [[ -f ".cursorrules" ]]; then
        pass "cursor wired (legacy .cursorrules)"
      else
        err "cursor declared but no .cursor/rules/*.mdc found"
      fi
      ;;
    opencode)
      if [[ -d ".opencode/agents" ]] && ls .opencode/agents/*.md >/dev/null 2>&1; then
        pass "opencode wired (.opencode/agents/*.md present)"
      else
        err "opencode declared but no .opencode/agents/*.md found"
      fi
      ;;
  esac
done

# ─── Check 4: dispatch freshness ────────────────────────────────────────
# Catches leftover pre-v1.1 wiring that survived reinstalls: legacy
# `agents/<name>/` pointers, symlinked shared files, and legacy IDG name
# references (scribe). Warns, doesn't block — the files may still work,
# but are stale and confusing.
ui_section_out "Dispatch freshness"
FRESHNESS_FILES=("AGENTS.md" "CLAUDE.md" ".github/copilot-instructions.md" ".cursorrules")
for f in "${FRESHNESS_FILES[@]}"; do
  [[ -e "$f" ]] || continue
  if [[ -L "$f" ]]; then
    err "$f is a symlink — shared dispatch files must be real composable files. Re-run 'eidolons sync --force'."
    continue
  fi
  if grep -Eq '@?\.?/?agents/(atlas|apivr|spectra|idg|scribe|forge)/' "$f" 2>/dev/null; then
    err "$f contains legacy agents/<name>/ pointers (pre-v1.1 paths). Delete the Eidolon block(s) and re-run 'eidolons sync --force'."
    continue
  fi
  if grep -q '@?\.?/?agents/scribe\|scribe/agent\.md' "$f" 2>/dev/null; then
    err "$f references legacy 'scribe' identifier (renamed to 'idg' in v1.1.1)."
    continue
  fi
  pass "$f clean (no stale pointers)"
done

# ─── Check 5: release integrity ─────────────────────────────────────────
# Read-only summary derived from eidolons.lock's `verification` field. We do
# not re-fetch the roster or recompute hashes here — that's `eidolons verify`'s
# job. Doctor surfaces what was recorded at sync/upgrade time so a stale lock
# is visible without leaving cwd. A `MISMATCH` outcome is treated as a hard
# error (something has drifted since sync); `verified` and `legacy-warning`
# are informational.
ui_section_out "Release integrity"
if [[ -f "$PROJECT_LOCK" ]]; then
  LOCK_JSON_DOCTOR="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null || echo '{}')"
  member_names="$(echo "$LOCK_JSON_DOCTOR" | jq -r '(.members // [])[].name')"
  if [[ -z "$member_names" ]]; then
    pass "No members locked — integrity check skipped"
  else
    while IFS= read -r mname; do
      [[ -n "$mname" ]] || continue
      mver="$(echo "$LOCK_JSON_DOCTOR" | jq -r --arg n "$mname" \
        '(.members // [])[] | select(.name == $n) | .version // ""')"
      mverif="$(echo "$LOCK_JSON_DOCTOR" | jq -r --arg n "$mname" \
        '(.members // [])[] | select(.name == $n) | .verification // ""')"
      case "$mverif" in
        verified)
          pass "$mname@$mver release integrity verified"
          ;;
        legacy-warning|"")
          # Compatibility mode or pre-integrity lock — informational, not blocking.
          printf "  %s·%s %s@%s no roster release metadata (legacy)\n" \
            "${YELLOW:-}" "${RESET:-}" "$mname" "$mver"
          ;;
        missing)
          err "$mname@$mver MISMATCH — release metadata missing under strict enforcement"
          ;;
        *)
          err "$mname@$mver unknown verification status: $mverif"
          ;;
      esac
    done <<< "$member_names"
  fi
else
  printf "  %s·%s eidolons.lock missing — integrity check deferred\n" \
    "${YELLOW:-}" "${RESET:-}"
fi

# ─── Summary ────────────────────────────────────────────────────────────
echo ""
if (( ERRORS == 0 )); then
  ok "All checks passed."
  exit 0
else
  warn "$ERRORS issue(s) found."
  if [[ "$FIX" == "true" ]]; then
    say "Attempting repairs via 'eidolons sync'..."
    exec bash "$SELF_DIR/sync.sh"
  else
    echo ""
    echo "Run 'eidolons doctor --fix' to attempt repairs, or 'eidolons sync' manually."
    exit 1
  fi
fi
