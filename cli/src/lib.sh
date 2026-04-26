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

# ─── Bash 3.2-portable timeout wrapper ────────────────────────────────────
# with_timeout SECONDS CMD ARGS...
# Runs CMD with the given timeout. Returns CMD's exit code on completion,
# or 124 (GNU timeout convention) when the timer fires. macOS bash 3.2
# safe — no `wait -n`, no GNU-only `timeout` binary required.
with_timeout() {
  local secs="$1"; shift
  if [[ -z "${1:-}" ]]; then
    return 2
  fi
  "$@" &
  local pid=$!
  ( sleep "$secs" && kill -9 "$pid" 2>/dev/null ) &
  local timer=$!
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  # If the timer-killer is still alive, the command completed first; reap it.
  if kill -0 "$timer" 2>/dev/null; then
    kill "$timer" 2>/dev/null || true
    wait "$timer" 2>/dev/null || true
  else
    # Timer fired — command was killed.
    wait "$timer" 2>/dev/null || true
    rc=124
  fi
  return "$rc"
}

# ─── Nexus version probes ─────────────────────────────────────────────────
# nexus_current_tag → echoes the exact-match tag at $NEXUS HEAD, or short SHA
#                     when not on a tag, or "unknown" when nexus has no .git.
nexus_current_tag() {
  if [[ ! -d "$NEXUS/.git" ]]; then
    echo "unknown"
    return 0
  fi
  local tag
  tag="$(git -C "$NEXUS" describe --tags --exact-match HEAD 2>/dev/null || true)"
  if [[ -n "$tag" ]]; then
    echo "$tag"
    return 0
  fi
  git -C "$NEXUS" rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

# nexus_current_commit → echoes the full SHA at HEAD, or "unknown".
nexus_current_commit() {
  if [[ ! -d "$NEXUS/.git" ]]; then
    echo "unknown"
    return 0
  fi
  git -C "$NEXUS" rev-parse HEAD 2>/dev/null || echo "unknown"
}

# nexus_latest_tag → highest vX.Y.Z tag from the nexus remote.
# Echoes the empty string + returns non-zero when the probe fails (offline,
# DNS error, timeout). 10-second cap via with_timeout.
nexus_latest_tag() {
  local repo="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
  local tmp; tmp="$(mktemp)"
  if with_timeout 10 git ls-remote --tags --refs "$repo" >"$tmp" 2>/dev/null; then
    local latest
    latest="$(awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+$/ { sub("refs/tags/", "", $2); print $2 }' "$tmp" \
              | sort -V | tail -1)"
    rm -f "$tmp"
    if [[ -n "$latest" ]]; then
      echo "$latest"
      return 0
    fi
    return 1
  fi
  rm -f "$tmp"
  return 1
}

# nexus_self_update TAG → fetch + reset --hard FETCH_HEAD against TAG.
# Returns 0 on success, 1 on fetch failure (state untouched on failure).
nexus_self_update() {
  local tag="$1"
  local repo="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
  [[ -d "$NEXUS/.git" ]] || return 1
  if ! git -C "$NEXUS" fetch --depth 1 origin "$tag" >/dev/null 2>&1; then
    return 1
  fi
  git -C "$NEXUS" reset --hard FETCH_HEAD >/dev/null 2>&1 || return 1
  return 0
}

# ─── SemVer helpers (pure bash, no external deps) ─────────────────────────
# semver_lt A B → exit 0 when A < B (strict), exit 1 otherwise.
# Uses `sort -V` for the comparison; both args must be plain X.Y.Z (no prefix).
semver_lt() {
  local a="$1" b="$2"
  if [[ "$a" == "$b" ]]; then
    return 1
  fi
  local first
  first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)"
  if [[ "$first" == "$a" ]]; then
    return 0
  fi
  return 1
}

# semver_satisfies CONSTRAINT VERSION → exit 0 when VERSION satisfies CONSTRAINT.
# CONSTRAINT may be "^X.Y.Z", "~X.Y.Z", "=X.Y.Z" or bare "X.Y.Z".
# Caret/tilde follow npm/cargo SemVer conventions.
semver_satisfies() {
  local constraint="$1" version="$2"
  local op="" base="" cmajor cminor _cpatch vmajor vminor _vpatch
  case "$constraint" in
    ^*) op="^"; base="${constraint#^}" ;;
    ~*) op="~"; base="${constraint#~}" ;;
    =*) op="="; base="${constraint#=}" ;;
    *)  op="="; base="$constraint" ;;
  esac

  # Validate both as X.Y.Z. If either malformed, fall back to literal equality.
  case "$base" in
    [0-9]*.[0-9]*.[0-9]*) : ;;
    *) [[ "$base" == "$version" ]] && return 0 || return 1 ;;
  esac
  case "$version" in
    [0-9]*.[0-9]*.[0-9]*) : ;;
    *) return 1 ;;
  esac

  cmajor="${base%%.*}"
  cminor="${base#*.}"; cminor="${cminor%%.*}"
  _cpatch="${base##*.}"
  vmajor="${version%%.*}"
  vminor="${version#*.}"; vminor="${vminor%%.*}"
  _vpatch="${version##*.}"

  # version must be >= base
  if semver_lt "$version" "$base"; then
    return 1
  fi

  case "$op" in
    =)
      [[ "$version" == "$base" ]] && return 0 || return 1
      ;;
    ~)
      # >= base, < base.major.(base.minor + 1).0
      [[ "$vmajor" == "$cmajor" && "$vminor" == "$cminor" ]] && return 0 || return 1
      ;;
    ^)
      if [[ "$cmajor" == "0" ]]; then
        # ^0.Y.Z → >= base, < 0.(Y+1).0  (npm semantics)
        [[ "$vmajor" == "0" && "$vminor" == "$cminor" ]] && return 0 || return 1
      else
        # ^X.Y.Z → >= base, < (X+1).0.0
        [[ "$vmajor" == "$cmajor" ]] && return 0 || return 1
      fi
      ;;
  esac
  return 1
}

# ─── Lockfile readers ─────────────────────────────────────────────────────
# lock_member_version NAME → echoes the resolved version for NAME from
# eidolons.lock, or empty string if absent / no lockfile.
lock_member_version() {
  local name="$1"
  [[ -f "$PROJECT_LOCK" ]] || { echo ""; return 0; }
  yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r --arg n "$name" '(.members // [])[] | select(.name == $n) | .version' \
    | head -1
}

# lock_member_resolved NAME → echoes the resolved commit fragment for NAME, or "".
lock_member_resolved() {
  local name="$1"
  [[ -f "$PROJECT_LOCK" ]] || { echo ""; return 0; }
  yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r --arg n "$name" '(.members // [])[] | select(.name == $n) | .resolved // ""' \
    | head -1
}
