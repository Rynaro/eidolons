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
  - Each installed Eidolon has its files in agents/<n>/
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
manifest_members | while read -r name; do
  target="./agents/$name"
  if [[ ! -d "$target" ]]; then
    err "$name declared but not installed at $target"
    continue
  fi
  if [[ -f "$target/install.manifest.json" ]]; then
    if jq -e . "$target/install.manifest.json" >/dev/null 2>&1; then
      pass "$name installed with valid manifest"
    else
      err "$name has corrupt install.manifest.json"
    fi
  else
    err "$name missing install.manifest.json (not fully EIIS-conformant)"
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
