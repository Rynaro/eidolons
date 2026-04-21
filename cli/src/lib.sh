#!/usr/bin/env bash
#
# cli/src/lib.sh — shared helpers for eidolons subcommands.
# Source at the top of any subcommand script: . "$(dirname "$0")/lib.sh"
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Re-derive EIDOLONS_HOME + NEXUS from environment or script location.
EIDOLONS_HOME="${EIDOLONS_HOME:-$HOME/.eidolons}"
NEXUS="${EIDOLONS_NEXUS:-$EIDOLONS_HOME/nexus}"
CACHE_DIR="$EIDOLONS_HOME/cache"
ROSTER_FILE="$NEXUS/roster/index.yaml"

mkdir -p "$CACHE_DIR"

# ─── Colors ────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; BLUE=""; RESET=""
fi

# ─── Logging ───────────────────────────────────────────────────────────────
say()   { printf "%s▸%s %s\n"  "$BOLD"   "$RESET" "$*"; }
ok()    { printf "%s✓%s %s\n"  "$GREEN"  "$RESET" "$*"; }
info()  { printf "%s·%s %s\n"  "$BLUE"   "$RESET" "$*"; }
warn()  { printf "%s⚠%s %s\n"  "$YELLOW" "$RESET" "$*" >&2; }
die()   { printf "%s✗%s %s\n"  "$RED"    "$RESET" "$*" >&2; exit 1; }

# ─── YAML → JSON ──────────────────────────────────────────────────────────
# Preferred: yq (mikefarah/yq or kislyuk/yq). Fallback: python3. Last resort: die.
yaml_to_json() {
  local file="$1"
  if command -v yq >/dev/null 2>&1; then
    # Handle both mikefarah/yq (Go) and kislyuk/yq (Python wrapper)
    if yq --version 2>&1 | grep -qi "mikefarah"; then
      yq -o=json eval '.' "$file"
    else
      yq . "$file"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys, json, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$file"
  else
    die "Need yq or python3 to parse YAML. Install yq: https://github.com/mikefarah/yq"
  fi
}

# ─── Roster queries ───────────────────────────────────────────────────────
# roster_list_names        → names, one per line
# roster_get NAME          → JSON object for that Eidolon (or exits 1)
# roster_preset_members P  → preset members, one per line
roster_list_names() {
  yaml_to_json "$ROSTER_FILE" | jq -r '.eidolons[].name'
}
roster_get() {
  local name="$1"
  local result
  result="$(yaml_to_json "$ROSTER_FILE" \
    | jq --arg n "$name" '.eidolons[] | select(.name == $n or ((.aliases // []) | index($n) != null))')"
  if [[ -z "$result" || "$result" == "null" ]]; then
    die "Eidolon '$name' not found in roster. Try: eidolons list"
  fi
  echo "$result"
}
roster_preset_members() {
  local preset="$1"
  yaml_to_json "$ROSTER_FILE" \
    | jq -r --arg p "$preset" '.presets[$p].members[]?' \
    | grep -v '^$' \
    || die "Preset '$preset' not found. Try: eidolons list --presets"
}
roster_presets() {
  yaml_to_json "$ROSTER_FILE" | jq -r '.presets | keys[]'
}

# ─── Host detection ───────────────────────────────────────────────────────
# Detect which hosts are in use in the current project (cwd).
# Emits: one host per line from {claude-code, copilot, cursor, opencode}
detect_hosts() {
  local hosts=()
  [[ -f "CLAUDE.md"      || -d ".claude"              ]] && hosts+=("claude-code")
  [[ -d ".github"         || -f "AGENTS.md"            ]] && hosts+=("copilot")
  [[ -d ".cursor"         || -f ".cursorrules"         ]] && hosts+=("cursor")
  [[ -d ".opencode"                                    ]] && hosts+=("opencode")
  printf "%s\n" "${hosts[@]}"
}

# ─── Eidolon repo fetching ────────────────────────────────────────────────
# fetch_eidolon NAME VERSION → echoes path to cached clone
fetch_eidolon() {
  local name="$1" version="${2:-latest}"
  local entry; entry="$(roster_get "$name")"
  local repo; repo="$(echo "$entry" | jq -r '.source.repo')"
  local ref
  if [[ "$version" == "latest" ]]; then
    ref="$(echo "$entry" | jq -r '.source.default_ref')"
  else
    ref="v$version"
  fi

  local clone_dir="$CACHE_DIR/${name}@${version}"
  if [[ ! -d "$clone_dir/.git" ]]; then
    say "Fetching $name@$version from github.com/$repo"
    git clone --depth 1 --branch "$ref" "https://github.com/$repo" "$clone_dir" >/dev/null 2>&1 \
      || die "Failed to clone github.com/$repo at $ref"
  else
    info "Using cached $name@$version"
  fi
  echo "$clone_dir"
}

# ─── EIIS conformance check ───────────────────────────────────────────────
# Minimal inline check — the full standalone checker lives in Rynaro/eidolons-eiis
eiis_check() {
  local dir="$1"
  local name="$2"
  local required=( "AGENTS.md" "CLAUDE.md" "install.sh" "agent.md" "README.md" )
  local missing=()
  for f in "${required[@]}"; do
    [[ -f "$dir/$f" ]] || missing+=("$f")
  done
  if (( ${#missing[@]} > 0 )); then
    warn "$name is not fully EIIS-conformant (missing: ${missing[*]})"
    warn "  Continuing anyway. Run 'eidolons doctor' after install for full report."
    return 1
  fi
  return 0
}

# ─── Project manifest (eidolons.yaml) ─────────────────────────────────────
PROJECT_MANIFEST="eidolons.yaml"
PROJECT_LOCK="eidolons.lock"

manifest_exists() { [[ -f "$PROJECT_MANIFEST" ]]; }

# Read installed members from eidolons.yaml → one name per line
manifest_members() {
  [[ -f "$PROJECT_MANIFEST" ]] || return 0
  yaml_to_json "$PROJECT_MANIFEST" | jq -r '.members[].name // empty'
}
