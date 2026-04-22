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
echo "${BOLD}Manifest + lock${RESET}"
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
echo ""
echo "${BOLD}Installed members${RESET}"
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

# ─── Check 3: host wiring ───────────────────────────────────────────────
echo ""
echo "${BOLD}Host wiring${RESET}"
hosts="$(yaml_to_json "$PROJECT_MANIFEST" | jq -r '.hosts.wire[]')"
for host in $hosts; do
  case "$host" in
    claude-code)
      [[ -f "CLAUDE.md" ]] && pass "CLAUDE.md present (claude-code)" || err "CLAUDE.md missing for claude-code"
      ;;
    copilot)
      if [[ -f ".github/copilot-instructions.md" || -f "AGENTS.md" ]]; then
        pass "Copilot dispatch present"
      else
        err "No AGENTS.md or .github/copilot-instructions.md for copilot"
      fi
      ;;
    cursor)
      [[ -d ".cursor" || -f ".cursorrules" ]] && pass ".cursor/ or .cursorrules present" \
        || err "No .cursor/ or .cursorrules for cursor"
      ;;
    opencode)
      [[ -d ".opencode" ]] && pass ".opencode/ present" || err "No .opencode/ for opencode"
      ;;
  esac
done

# ─── Check 4: dispatch freshness ────────────────────────────────────────
# Catches leftover pre-v1.1 wiring that survived reinstalls: legacy
# `agents/<name>/` pointers, symlinked shared files, and legacy IDG name
# references (scribe). Warns, doesn't block — the files may still work,
# but are stale and confusing.
echo ""
echo "${BOLD}Dispatch freshness${RESET}"
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
