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

# ─── UI layer (theme + panels) ─────────────────────────────────────────────
# theme.sh detects fancy vs plain mode and exports color vars (BOLD, DIM,
# GREEN, YELLOW, RED, BLUE, CYAN, AMBER, MUTED, RESET) plus role aliases
# (UI_PRIMARY, UI_SUCCESS, UI_INFO, UI_WARN, UI_ERROR, UI_ACCENT,
# UI_MUTED). Plain mode → all empty strings, identical to the historical
# behaviour every test asserts on. panel.sh adds ui_banner / ui_section /
# ui_divider / ui_kv on top.
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui/theme.sh"
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui/panel.sh"

# ─── Logging ───────────────────────────────────────────────────────────────
# All log output goes to stderr so functions whose stdout is captured by
# the caller (e.g. fetch_eidolon, roster_preset_members) can emit progress
# without corrupting their return value.
#
# Icon glyphs (▸✓·⚠✗) are pinned by tests — keep them as-is. Colors are
# now sourced from theme.sh role aliases instead of raw ANSI vars, so a
# theme swap automatically restyles all logs.
say()   { printf "%s%s%s %s\n" "${BOLD}"        "${GLYPH_PROGRESS}" "${RESET}" "$*" >&2; }
ok()    { printf "%s%s%s %s\n" "${UI_SUCCESS}"  "${GLYPH_OK}"       "${RESET}" "$*" >&2; }
info()  { printf "%s%s%s %s\n" "${UI_INFO}"     "${GLYPH_INFO}"     "${RESET}" "$*" >&2; }
warn()  { printf "%s%s%s %s\n" "${UI_WARN}"     "${GLYPH_WARN}"     "${RESET}" "$*" >&2; }
die()   { printf "%s%s%s %s\n" "${UI_ERROR}"    "${GLYPH_ERROR}"    "${RESET}" "$*" >&2; exit 1; }

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
  elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    python3 -c "import sys, json, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$file"
  else
    die "Cannot parse YAML: neither yq nor python3+PyYAML is available.
  Fix (recommended): rerun the bootstrap installer to auto-install yq:
      curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
  Or install yq manually: https://github.com/mikefarah/yq/releases
  Or install PyYAML:      pip install --user pyyaml"
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
# Emits: one host per line from {claude-code, copilot, cursor, opencode, codex}
#
# AGENTS.md / codex co-ownership truth table (T.3 of openai-codex-host-support):
#   .codex/  present                              → codex (definitive Codex-only signal)
#   AGENTS.md only (no .github/, no .codex/)      → codex (NOT copilot)
#   .github/ only (no AGENTS.md, no .codex/)      → copilot
#   AGENTS.md AND .github/ (no .codex/)           → BOTH copilot and codex
#   .codex/ AND .github/                          → BOTH codex and copilot
# Sources:
#   https://developers.openai.com/codex/guides/agents-md
#   https://developers.openai.com/codex/subagents
detect_hosts() {
  local hosts=()
  local has_agents_md=0 has_github=0 has_codex_dir=0

  [[ -f "AGENTS.md" ]] && has_agents_md=1
  [[ -d ".github"  ]] && has_github=1
  [[ -d ".codex"   ]] && has_codex_dir=1

  [[ -f "CLAUDE.md" || -d ".claude"      ]] && hosts+=("claude-code")

  # Codex / Copilot disambiguation. Order matters because tests check for
  # presence/absence of specific tokens; we keep emission order stable.
  if (( has_codex_dir == 1 )); then
    hosts+=("codex")
    if (( has_github == 1 )); then
      hosts+=("copilot")
    fi
  elif (( has_agents_md == 1 && has_github == 1 )); then
    hosts+=("copilot")
    hosts+=("codex")
  elif (( has_agents_md == 1 )); then
    hosts+=("codex")
  elif (( has_github == 1 )); then
    hosts+=("copilot")
  fi

  [[ -d ".cursor" || -f ".cursorrules"   ]] && hosts+=("cursor")
  [[ -d ".opencode"                      ]] && hosts+=("opencode")
  if (( ${#hosts[@]} > 0 )); then
    printf "%s\n" "${hosts[@]}"
  fi
  return 0
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
# Delegates to the standalone checker at Rynaro/eidolons-eiis when reachable,
# falls back to the inline file-existence check when offline.

# eiis_required_version → reads `eiis_required` from roster/index.yaml
eiis_required_version() {
  local roster="$NEXUS/roster/index.yaml"
  [[ -f "$roster" ]] || { echo "1.1"; return; }
  yaml_to_json "$roster" 2>/dev/null | jq -r '.eiis_required // "1.1"'
}

# resolve_eiis_tag REQ → echoes the tag to clone (e.g. "1.1" → "1.1.4")
# `eiis_required` in the roster is a major.minor compat declaration; the
# actual EIIS repo tags are full SemVer (v1.0.0, v1.1.0, …). When REQ is
# already a full SemVer it round-trips unchanged.
resolve_eiis_tag() {
  local req="$1"
  if [[ "$req" =~ ^[0-9]+\.[0-9]+$ ]]; then
    local resolved
    resolved=$(git ls-remote --tags --refs https://github.com/Rynaro/eidolons-eiis 2>/dev/null \
      | awk -v p="refs/tags/v${req}." '$2 ~ "^"p { sub("refs/tags/v", "", $2); print $2 }' \
      | sort -V \
      | tail -1)
    [[ -n "$resolved" ]] && { echo "$resolved"; return; }
  fi
  echo "$req"
}

# fetch_eiis [VERSION] → echoes path to cached clone, or returns non-zero on failure
fetch_eiis() {
  local version="${1:-$(eiis_required_version)}"
  local resolved; resolved="$(resolve_eiis_tag "$version")"
  local clone_dir="$CACHE_DIR/eiis@${resolved}"
  if [[ ! -d "$clone_dir/.git" ]]; then
    mkdir -p "$CACHE_DIR"
    git clone --depth 1 --branch "v$resolved" \
      "https://github.com/Rynaro/eidolons-eiis" "$clone_dir" >/dev/null 2>&1 \
      || return 1
  fi
  echo "$clone_dir"
}

eiis_check() {
  local dir="$1"
  local name="$2"
  local checker_dir
  if checker_dir="$(fetch_eiis 2>/dev/null)" \
     && [[ -n "$checker_dir" && -x "$checker_dir/conformance/check.sh" ]]; then
    if bash "$checker_dir/conformance/check.sh" "$dir" >/dev/null 2>&1; then
      return 0
    fi
    warn "$name fails EIIS conformance"
    warn "  Re-run for details: bash $checker_dir/conformance/check.sh \"$dir\""
    return 1
  fi

  # Offline fallback — keep behaviour byte-compatible with v1.0 inline check.
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
