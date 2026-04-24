#!/usr/bin/env bash
# commands/aci.sh — wire the atlas-aci MCP server into a consumer project.
#
# Ships from Rynaro/ATLAS and is installed by ATLAS's install.sh into
# ./.eidolons/atlas/commands/aci.sh. Auto-surfaced by the nexus dispatcher
# (cli/src/dispatch_eidolon.sh) as `eidolons atlas aci [OPTIONS]`.
#
# Full decision-ready spec: docs/specs/atlas-aci-integration.md in the
# Rynaro/eidolons nexus repo. Section anchors throughout this file point
# at the governing clauses.
#
# ═══════════════════════════════════════════════════════════════════════════
# IMPORTANT INVARIANTS (violating these is a P0 bug):
#   - Layer-2 write boundary (P4 / D3): NEVER write outside $PWD.
#     Especially NOT ~/Library/Application Support/, NOT ~/.config/,
#     NOT ~/.claude/, NOT ~/.cursor/, NOT $EIDOLONS_HOME.
#   - Idempotency model per file type (§4.7):
#       .mcp.json / .cursor/mcp.json : jq merge on mcpServers."atlas-aci"
#       .github/agents/*.agent.md    : yq merge on list entry name: atlas-aci
#       .gitignore                   : append-if-absent on line '.atlas/'
#   - All progress to stderr (P6). Stdout stays empty on --install /
#     --remove success; dry-run stdout emits CREATE|MODIFY|REMOVE|INDEX.
#   - Bash 3.2 compatible (P5): no associative arrays, no ${var,,},
#     no readarray/mapfile, no &>>. Atomic tmpfile + mv everywhere.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Pinned atlas-aci upstream (v1: commit SHA per G3 / D4) ───────────────
# When atlas-aci cuts its first tagged release, bump to a version string
# and revisit D4 (see §9 follow-up F1 in the spec).
ATLAS_ACI_REPO="https://github.com/Rynaro/atlas-aci"
ATLAS_ACI_PIN="main"  # v1: no tags upstream; track main until F1 triggers.

# ─── Logging (mirrors cli/src/lib.sh — P6: everything to stderr) ──────────
# Kept local so this script is self-sufficient when the dispatcher exec's
# it with cwd at the consumer project root (no nexus lib is sourced).
if [ -t 2 ]; then
  _C_B=$'\033[1m'; _C_G=$'\033[32m'; _C_Y=$'\033[33m'
  _C_R=$'\033[31m'; _C_C=$'\033[36m'; _C_RST=$'\033[0m'
else
  _C_B=""; _C_G=""; _C_Y=""; _C_R=""; _C_C=""; _C_RST=""
fi
say()  { printf "%s▸%s %s\n" "$_C_B"  "$_C_RST" "$*" >&2; }
ok()   { printf "%s✓%s %s\n" "$_C_G"  "$_C_RST" "$*" >&2; }
info() { printf "%s·%s %s\n" "$_C_C"  "$_C_RST" "$*" >&2; }
warn() { printf "%s⚠%s %s\n" "$_C_Y"  "$_C_RST" "$*" >&2; }
err()  { printf "%s✗%s %s\n" "$_C_R"  "$_C_RST" "$*" >&2; }

# Hard exits — each maps to a §4.8 exit code.
exit_usage()     { err "$*"; exit 2; }  # usage error
exit_no_atlas()  { err "$*"; exit 3; }  # ATLAS not installed
exit_no_host()   { err "$*"; exit 4; }  # no MCP-capable host
exit_prereq()    { err "$*"; exit 5; }  # prereq missing
exit_index_fail(){ err "$*"; exit 6; }  # atlas-aci index failed
die()            { err "$*"; exit 1; }  # unexpected runtime error

# ─── Args ─────────────────────────────────────────────────────────────────
ACTION="install"       # install | remove
DRY_RUN=false
NON_INTERACTIVE=false
HOSTS_EXPLICIT=""      # CSV of user-specified hosts

usage() {
  cat <<'EOF'
eidolons atlas aci — wire atlas-aci MCP server into this project

Usage: eidolons atlas aci [OPTIONS]

Options:
  --install              (default) Verify prereqs, run atlas-aci index,
                         append .atlas/ to .gitignore, and write MCP
                         config for atlas-aci into every detected
                         MCP-capable host in cwd.
  --remove               Remove atlas-aci entries from MCP config in cwd.
                         Idempotent. Does NOT delete .atlas/.
  --host HOST            Restrict to one host: claude-code, cursor,
                         copilot. Repeat for multiple. Overrides auto-
                         detection.
  --dry-run              Print every file that would be created /
                         modified / removed. Touch no disk state.
                         Does not run `atlas-aci index`.
  --non-interactive      Fail on any prompt (for CI).
  -h, --help             Show this help.

Exit codes:
  0  success / no-op
  2  usage error
  3  ATLAS not installed in this project
  4  no MCP-capable host detected and --host not provided
  5  atlas-aci prereq missing (uv, rg, python3>=3.11, or atlas-aci)
  6  atlas-aci index failed
  1  unexpected runtime error

Scope: project-local files only. Never writes outside $PWD.
User-level Claude Desktop config is deferred to a future nexus
built-in (see docs/atlas-aci.md in Rynaro/eidolons).
EOF
}

_action_seen=false
_add_host() {
  case "$1" in
    claude-code|cursor|copilot) ;;
    *) exit_usage "Unknown --host value: $1 (want: claude-code, cursor, copilot)" ;;
  esac
  if [ -z "$HOSTS_EXPLICIT" ]; then
    HOSTS_EXPLICIT="$1"
  else
    HOSTS_EXPLICIT="$HOSTS_EXPLICIT,$1"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install)
      if [ "$_action_seen" = "true" ] && [ "$ACTION" != "install" ]; then
        exit_usage "Conflicting flags: --install and --$ACTION"
      fi
      ACTION="install"; _action_seen=true; shift ;;
    --remove)
      if [ "$_action_seen" = "true" ] && [ "$ACTION" != "remove" ]; then
        exit_usage "Conflicting flags: --remove and --$ACTION"
      fi
      ACTION="remove"; _action_seen=true; shift ;;
    --dry-run)         DRY_RUN=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --host)
      [ "$#" -ge 2 ] || exit_usage "--host requires a value"
      _add_host "$2"; shift 2 ;;
    --host=*)
      _add_host "${1#--host=}"; shift ;;
    -h|--help)         usage; exit 0 ;;
    *) exit_usage "Unknown option: $1" ;;
  esac
done

# ─── §4.3 first read: refuse to run if ATLAS is not installed ─────────────
# This runs BEFORE prereq checks so the user gets the clearest possible
# error ("you installed the wrong thing first") instead of a prereq nag.
if [ ! -f "./.eidolons/atlas/install.manifest.json" ]; then
  exit_no_atlas "atlas-aci: ATLAS is not installed in this project.
  Expected: ./.eidolons/atlas/install.manifest.json
  Fix:      eidolons sync   (with atlas in eidolons.yaml)"
fi

# ─── Helpers ──────────────────────────────────────────────────────────────

# python3_at_least MIN_MAJOR MIN_MINOR — returns 0 if python3 --version
# reports at least MIN_MAJOR.MIN_MINOR. Stays in bash-3.2 territory by
# avoiding ${var,,} and arithmetic on string slices.
python3_at_least() {
  local want_major="$1" want_minor="$2"
  local raw major minor
  raw="$(python3 --version 2>&1 | awk '{print $2}')"
  [ -n "$raw" ] || return 1
  major="$(echo "$raw" | awk -F. '{print $1}')"
  minor="$(echo "$raw" | awk -F. '{print $2}')"
  # Reject non-numeric (defensive — upstream python3 always emits numeric).
  case "$major" in ''|*[!0-9]*) return 1 ;; esac
  case "$minor" in ''|*[!0-9]*) return 1 ;; esac
  if [ "$major" -gt "$want_major" ]; then return 0; fi
  if [ "$major" -lt "$want_major" ]; then return 1; fi
  if [ "$minor" -ge "$want_minor" ]; then return 0; fi
  return 1
}

# yq_is_mikefarah — distinguishes mikefarah/yq (Go) from kislyuk/yq (Python
# wrapper). Their CLIs differ materially; we only support mikefarah/yq
# for the frontmatter edits because kislyuk/yq cannot do in-place YAML
# round-tripping through a Markdown preamble.
yq_is_mikefarah() {
  yq --version 2>&1 | grep -qi 'mikefarah'
}

# Dry-run channel: stdout gets `CREATE|MODIFY|REMOVE|INDEX <path>` lines
# (§4.9). Everything else (progress, warnings) goes to stderr via say/info.
emit_action() {
  if [ "$DRY_RUN" = "true" ]; then
    printf "%s %s\n" "$1" "$2"
  fi
}

# Atomic write helper — writes $2 content to temp file in same dir as
# target $1, then mv's. Bash-3.2-safe.
atomic_write() {
  local dest="$1" content="$2"
  local dir tmp
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  tmp="$(mktemp "${dir}/.atlas-aci-XXXXXX")" || die "mktemp failed in $dir"
  printf "%s" "$content" > "$tmp" || { rm -f "$tmp"; die "write failed: $tmp"; }
  mv "$tmp" "$dest" || { rm -f "$tmp"; die "atomic rename failed: $dest"; }
}

# ─── §4.2 Prereq checks (install path only) ───────────────────────────────
check_prereqs() {
  local missing=""
  if ! command -v uv >/dev/null 2>&1; then
    exit_prereq "atlas-aci prereq missing: 'uv' not on PATH.
  Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
  if ! command -v rg >/dev/null 2>&1; then
    exit_prereq "atlas-aci prereq missing: 'rg' (ripgrep) not on PATH.
  Install with: brew install ripgrep   # macOS
           or:  apt-get install ripgrep # Debian/Ubuntu"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    exit_prereq "atlas-aci prereq missing: python3 not on PATH.
  Install Python 3.11+ via uv or your OS package manager."
  fi
  if ! python3_at_least 3 11; then
    local raw
    raw="$(python3 --version 2>&1 | awk '{print $2}')"
    exit_prereq "atlas-aci prereq: python3 >= 3.11 required (have: ${raw:-unknown}).
  Install Python 3.11+ via uv or your OS package manager."
  fi
  if ! command -v atlas-aci >/dev/null 2>&1; then
    exit_prereq "atlas-aci prereq missing: 'atlas-aci' binary not on PATH.
  Install with:
    git clone ${ATLAS_ACI_REPO} && cd atlas-aci/mcp-server && uv sync && uv tool install ."
  fi
  # yq + jq: used for config edits. Both are expected on every Eidolons
  # consumer box (cli/install.sh installs yq) but we still guard.
  if ! command -v jq >/dev/null 2>&1; then
    exit_prereq "atlas-aci prereq missing: 'jq' not on PATH.
  Install with: brew install jq   # macOS
           or:  apt-get install jq # Debian/Ubuntu"
  fi
  if ! command -v yq >/dev/null 2>&1; then
    exit_prereq "atlas-aci prereq missing: 'yq' not on PATH.
  Install with: brew install yq   # macOS, or see https://github.com/mikefarah/yq/releases"
  fi
  if ! yq_is_mikefarah; then
    exit_prereq "atlas-aci prereq: 'yq' must be mikefarah/yq (Go).
  Detected: $(yq --version 2>&1 | head -n 1)
  Install with: brew install yq   (macOS) / see https://github.com/mikefarah/yq/releases"
  fi
  [ -n "$missing" ] || return 0
}

# ─── Host selection ───────────────────────────────────────────────────────
# If --host was supplied, honor it verbatim. Otherwise sniff cwd and
# pick only the MCP-capable hosts (claude-code, cursor, copilot).
# opencode is NOT included: its MCP capability is not confirmed in this
# spec revision (§2.1 G2).
detect_hosts_mcp() {
  local hosts=""
  if [ -f "CLAUDE.md" ] || [ -d ".claude" ]; then
    hosts="claude-code"
  fi
  if [ -d ".github" ] || [ -f "AGENTS.md" ]; then
    if [ -n "$hosts" ]; then hosts="${hosts},copilot"; else hosts="copilot"; fi
  fi
  if [ -d ".cursor" ] || [ -f ".cursorrules" ]; then
    if [ -n "$hosts" ]; then hosts="${hosts},cursor"; else hosts="cursor"; fi
  fi
  echo "$hosts"
}

resolve_hosts() {
  if [ -n "$HOSTS_EXPLICIT" ]; then
    echo "$HOSTS_EXPLICIT"
    return 0
  fi
  detect_hosts_mcp
}

# ─── .gitignore handling (§4.4, §4.7) ─────────────────────────────────────
# Append-only, line-match on '.atlas/'. Whitespace-insensitive: we match
# the *.atlas/* token regardless of surrounding whitespace, but NOT
# trailing comments on the same line (because .gitignore does not
# support inline comments — a `.atlas/ # foo` line is literally the
# path `.atlas/ # foo`). The match rule is:
#   - Trim leading / trailing whitespace.
#   - Match exactly `.atlas/` or `.atlas` (tolerate missing slash).
gitignore_has_atlas_entry() {
  [ -f ".gitignore" ] || return 1
  # Use awk to trim and compare — portable on bash 3.2.
  awk '
    { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "");
      if ($0 == ".atlas/" || $0 == ".atlas") { found=1; exit }
    }
    END { exit (found ? 0 : 1) }
  ' .gitignore
}

ensure_gitignore() {
  if gitignore_has_atlas_entry; then
    info ".gitignore already contains .atlas/ — skipping"
    return 0
  fi
  if [ "$DRY_RUN" = "true" ]; then
    if [ -f ".gitignore" ]; then
      emit_action "MODIFY" ".gitignore"
    else
      emit_action "CREATE" ".gitignore"
    fi
    return 0
  fi
  if [ -f ".gitignore" ]; then
    # Append, preserving an existing trailing newline (add one if
    # missing). Atomic: write a new file, then mv.
    local tmp
    tmp="$(mktemp "./.atlas-aci-gi-XXXXXX")" || die "mktemp failed"
    cat ".gitignore" > "$tmp"
    # Ensure trailing newline before append.
    if [ -s "$tmp" ] && [ "$(tail -c 1 "$tmp" | od -An -c | tr -d ' ')" != "\\n" ]; then
      printf "\n" >> "$tmp"
    fi
    printf ".atlas/\n" >> "$tmp"
    mv "$tmp" ".gitignore" || { rm -f "$tmp"; die "rename .gitignore failed"; }
    ok "Appended .atlas/ to .gitignore"
  else
    atomic_write ".gitignore" ".atlas/"$'\n'
    ok "Created .gitignore with .atlas/"
  fi
}

# ─── atlas-aci index (§4.4 side effect) ───────────────────────────────────
# Runs BEFORE any MCP config writes so an index failure aborts cleanly
# (A13). Skipped if .atlas/manifest.yaml exists (T24).
run_index() {
  if [ -f "./.atlas/manifest.yaml" ]; then
    info ".atlas/manifest.yaml present — skipping re-index (delete .atlas/ to force)"
    return 0
  fi
  if [ "$DRY_RUN" = "true" ]; then
    emit_action "INDEX" ".atlas/"
    return 0
  fi
  say "Indexing project with atlas-aci (first run can take minutes on large repos)"
  if ! atlas-aci index \
         --repo "$PWD" \
         --langs ruby,python,javascript,typescript >&2; then
    exit_index_fail "atlas-aci index failed — aborting before MCP config writes.
  No MCP config files were modified."
  fi
  ok "Indexed → .atlas/"
}

# ─── JSON host writes: .mcp.json, .cursor/mcp.json (§4.4, §4.5) ──────────
# Idempotency primitive: object-key match on mcpServers."atlas-aci".
# jq merge on install; jq del on remove. Peer keys preserved (A11).
json_server_fragment() {
  # Emits the object fragment we merge under .mcpServers."atlas-aci".
  # Indentation managed by the final jq --indent 2 invocation.
  jq -n '{
    command: "atlas-aci",
    args: [
      "serve",
      "--repo", "${workspaceFolder}",
      "--memex-root", "${workspaceFolder}/.atlas/memex"
    ]
  }'
}

json_install() {
  local target="$1" existed
  if [ -f "$target" ]; then existed=true; else existed=false; fi

  if [ "$DRY_RUN" = "true" ]; then
    if [ "$existed" = "true" ]; then
      emit_action "MODIFY" "$target"
    else
      emit_action "CREATE" "$target"
    fi
    return 0
  fi

  local dir tmp merged base frag
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  tmp="$(mktemp "${dir}/.atlas-aci-mcp-XXXXXX")" || die "mktemp failed"

  frag="$(json_server_fragment)"

  if [ "$existed" = "true" ]; then
    # Validate existing JSON before we touch it. Invalid JSON = fail
    # closed; do not clobber user content.
    if ! jq empty "$target" >/dev/null 2>&1; then
      rm -f "$tmp"
      die "Existing $target is not valid JSON — refusing to overwrite. Fix manually."
    fi
    base="$(cat "$target")"
    merged="$(echo "$base" | jq --argjson s "$frag" \
      '.mcpServers = (.mcpServers // {}) | .mcpServers["atlas-aci"] = $s' \
      --indent 2)"
  else
    merged="$(jq -n --argjson s "$frag" \
      '{mcpServers: {"atlas-aci": $s}}' --indent 2)"
  fi

  printf "%s\n" "$merged" > "$tmp" || { rm -f "$tmp"; die "write failed: $tmp"; }
  mv "$tmp" "$target" || { rm -f "$tmp"; die "rename failed: $target"; }

  if [ "$existed" = "true" ]; then
    ok "Merged atlas-aci into $target"
  else
    ok "Created $target"
  fi
}

json_remove() {
  local target="$1"
  [ -f "$target" ] || { info "$target absent — nothing to remove"; return 0; }

  if ! jq empty "$target" >/dev/null 2>&1; then
    warn "$target is not valid JSON — skipping (manual fix required)"
    return 0
  fi

  # If atlas-aci key not present, nothing to do.
  if ! jq -e '.mcpServers["atlas-aci"] // empty' "$target" >/dev/null 2>&1; then
    info "$target has no mcpServers.atlas-aci entry — nothing to remove"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    emit_action "MODIFY" "$target"
    return 0
  fi

  local dir tmp after
  dir="$(dirname "$target")"
  tmp="$(mktemp "${dir}/.atlas-aci-mcp-XXXXXX")" || die "mktemp failed"
  after="$(jq 'del(.mcpServers["atlas-aci"])' "$target" --indent 2)"
  # If mcpServers is now an empty object, leave the empty object in
  # place rather than deleting the key — some hosts expect the key to
  # exist. This is deliberate: do not reshape beyond what we added.
  printf "%s\n" "$after" > "$tmp" || { rm -f "$tmp"; die "write failed: $tmp"; }
  mv "$tmp" "$target" || { rm -f "$tmp"; die "rename failed: $target"; }
  ok "Removed atlas-aci from $target"
}

# ─── Copilot host writes: .github/agents/*.agent.md (§4.4, §4.6) ─────────
# YAML frontmatter split: the file is a Markdown document with a leading
# `---\n<yaml>\n---\n<markdown body>`. We operate on the frontmatter in
# isolation (yq eval), then splice it back. Bodies are preserved byte-
# for-byte (T15).
#
# Idempotency: list-entry match on `name: atlas-aci` under
# tools.mcp_servers. yq replaces in place; peer entries preserved (T9c).
copilot_split_file() {
  # Reads $1; writes frontmatter to $2, body to $3. Returns 0 if a
  # well-formed frontmatter was found, 1 otherwise (caller treats as
  # "skip with a warning" per R6).
  local src="$1" fm_out="$2" body_out="$3"
  # A valid frontmatter is: line 1 is exactly '---', there's a second
  # '---' line later, both matched exactly.
  if [ "$(head -n 1 "$src")" != "---" ]; then
    return 1
  fi
  # Find the closing '---' line number (starting from line 2).
  local close_ln
  close_ln="$(awk 'NR>1 && $0=="---" { print NR; exit }' "$src")"
  [ -n "$close_ln" ] || return 1
  # Write frontmatter lines 2..(close_ln-1) to fm_out.
  local inner_end=$((close_ln - 1))
  if [ "$inner_end" -lt 2 ]; then
    # Empty frontmatter — yq can handle `{}` but we emit a blank.
    : > "$fm_out"
  else
    sed -n "2,${inner_end}p" "$src" > "$fm_out"
  fi
  # Body is everything after the closing ---.
  local body_start=$((close_ln + 1))
  # tail's -n +N means "starting at line N". If body is empty, produce
  # an empty file (not an error).
  tail -n "+${body_start}" "$src" > "$body_out" || true
  return 0
}

copilot_list_all_agents() {
  # Emit every .agent.md under .github/agents/ (newline-separated).
  # Safe if the dir or files don't exist.
  if [ ! -d ".github/agents" ]; then return 0; fi
  # shellcheck disable=SC2012
  ls -1 .github/agents 2>/dev/null | awk '/\.agent\.md$/ {print ".github/agents/"$0}'
}

copilot_install_one() {
  local target="$1"
  local fm body merged rebuilt tmp
  fm="$(mktemp "./.atlas-aci-fm-XXXXXX")" || die "mktemp failed"
  body="$(mktemp "./.atlas-aci-body-XXXXXX")" || die "mktemp failed"

  if ! copilot_split_file "$target" "$fm" "$body"; then
    rm -f "$fm" "$body"
    warn "$target has no YAML frontmatter — skipping (R6 fail-closed)"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    emit_action "MODIFY" "$target"
    rm -f "$fm" "$body"
    return 0
  fi

  # Ensure tools.mcp_servers exists as a list, then filter out any
  # pre-existing name: atlas-aci entry, then append our canonical
  # entry. This guarantees idempotent re-install.
  merged="$(yq eval '
    .tools = (.tools // {}) |
    .tools.mcp_servers = (.tools.mcp_servers // []) |
    .tools.mcp_servers = ([.tools.mcp_servers[] | select(.name != "atlas-aci")] + [{
      "name": "atlas-aci",
      "transport": "stdio",
      "command": ["atlas-aci", "serve", "--repo", "${workspaceFolder}", "--memex-root", "${workspaceFolder}/.atlas/memex"]
    }])
  ' "$fm")" || { rm -f "$fm" "$body"; die "yq merge failed on $target"; }

  # Splice back. Body preservation: we re-emit the body byte-for-byte.
  tmp="$(mktemp "./.atlas-aci-agent-XXXXXX")" || { rm -f "$fm" "$body"; die "mktemp failed"; }
  {
    printf -- "---\n"
    printf "%s\n" "$merged"
    printf -- "---\n"
    cat "$body"
  } > "$tmp" || { rm -f "$fm" "$body" "$tmp"; die "rebuild failed for $target"; }

  # Sanity: trailing newline in body was preserved by `cat`. Sanity:
  # yq output never carries a leading `---` (we strip that role).
  mv "$tmp" "$target" || { rm -f "$fm" "$body" "$tmp"; die "rename failed: $target"; }
  rm -f "$fm" "$body"
  ok "Merged atlas-aci into $target"
}

copilot_remove_one() {
  local target="$1"
  local fm body merged tmp
  fm="$(mktemp "./.atlas-aci-fm-XXXXXX")" || die "mktemp failed"
  body="$(mktemp "./.atlas-aci-body-XXXXXX")" || die "mktemp failed"

  if ! copilot_split_file "$target" "$fm" "$body"; then
    rm -f "$fm" "$body"
    info "$target has no YAML frontmatter — nothing to remove"
    return 0
  fi

  # If no atlas-aci entry exists, no-op.
  if ! yq eval '.tools.mcp_servers[]? | select(.name == "atlas-aci")' "$fm" \
       | grep -q '.' ; then
    rm -f "$fm" "$body"
    info "$target has no atlas-aci MCP entry — nothing to remove"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    emit_action "MODIFY" "$target"
    rm -f "$fm" "$body"
    return 0
  fi

  merged="$(yq eval '
    .tools.mcp_servers = ([.tools.mcp_servers[] | select(.name != "atlas-aci")])
  ' "$fm")" || { rm -f "$fm" "$body"; die "yq del failed on $target"; }

  tmp="$(mktemp "./.atlas-aci-agent-XXXXXX")" || { rm -f "$fm" "$body"; die "mktemp failed"; }
  {
    printf -- "---\n"
    printf "%s\n" "$merged"
    printf -- "---\n"
    cat "$body"
  } > "$tmp" || { rm -f "$fm" "$body" "$tmp"; die "rebuild failed for $target"; }
  mv "$tmp" "$target" || { rm -f "$fm" "$body" "$tmp"; die "rename failed: $target"; }
  rm -f "$fm" "$body"
  ok "Removed atlas-aci from $target"
}

# ─── Per-host dispatch ────────────────────────────────────────────────────
apply_host_install() {
  case "$1" in
    claude-code) json_install "./.mcp.json" ;;
    cursor)      json_install "./.cursor/mcp.json" ;;
    copilot)
      # If no .agent.md files exist, skip with info (T14).
      local agents files_found=false
      agents="$(copilot_list_all_agents)"
      if [ -z "$agents" ]; then
        info "copilot: no .github/agents/*.agent.md files found — skipping"
        return 0
      fi
      # IFS-split on newlines, bash-3.2-safe.
      local old_IFS="$IFS"
      IFS='
'
      for agent in $agents; do
        files_found=true
        IFS="$old_IFS"
        copilot_install_one "$agent"
        IFS='
'
      done
      IFS="$old_IFS"
      [ "$files_found" = "true" ] || info "copilot: no agent files processed"
      ;;
    *) warn "Unknown host: $1 (skipping)" ;;
  esac
}

apply_host_remove() {
  case "$1" in
    claude-code) json_remove "./.mcp.json" ;;
    cursor)      json_remove "./.cursor/mcp.json" ;;
    copilot)
      local agents
      agents="$(copilot_list_all_agents)"
      if [ -z "$agents" ]; then
        info "copilot: no .github/agents/*.agent.md files found — nothing to remove"
        return 0
      fi
      local old_IFS="$IFS"
      IFS='
'
      for agent in $agents; do
        IFS="$old_IFS"
        copilot_remove_one "$agent"
        IFS='
'
      done
      IFS="$old_IFS"
      ;;
    *) warn "Unknown host: $1 (skipping)" ;;
  esac
}

# ─── Main ─────────────────────────────────────────────────────────────────
main_install() {
  check_prereqs

  local hosts_csv
  hosts_csv="$(resolve_hosts)"
  if [ -z "$hosts_csv" ]; then
    exit_no_host "No MCP-capable host detected in this project, and --host was not supplied.
  Detectable hosts: claude-code, cursor, copilot
  Fix: run with e.g. --host claude-code"
  fi

  info "Hosts: $hosts_csv"
  [ "$DRY_RUN" = "true" ] && info "Dry-run mode — no files will be modified"

  # Ordering: .gitignore first (cheapest), then index (slowest — aborts
  # early if broken), then MCP writes. §A13 requires index failure to
  # precede config writes; that is enforced by this ordering.
  ensure_gitignore
  run_index

  local old_IFS="$IFS"
  IFS=','
  for h in $hosts_csv; do
    IFS="$old_IFS"
    apply_host_install "$h"
    IFS=','
  done
  IFS="$old_IFS"

  [ "$DRY_RUN" = "true" ] && return 0
  ok "atlas-aci wired into $hosts_csv"
}

main_remove() {
  # No prereq checks on remove: user may be removing BECAUSE a prereq
  # is broken. Only the ATLAS-installed guard (above) is required.
  local hosts_csv
  hosts_csv="$(resolve_hosts)"
  if [ -z "$hosts_csv" ]; then
    # On remove, "no host detected" is slightly different: the user
    # may have already cleaned up the .claude/.cursor/.github dirs.
    # Walk all known host files and no-op if absent. This keeps
    # `remove` idempotent even from a mostly-clean state.
    info "No MCP-capable host detected — sweeping known paths anyway"
    hosts_csv="claude-code,cursor,copilot"
  fi

  info "Hosts: $hosts_csv"
  [ "$DRY_RUN" = "true" ] && info "Dry-run mode — no files will be modified"

  local old_IFS="$IFS"
  IFS=','
  for h in $hosts_csv; do
    IFS="$old_IFS"
    apply_host_remove "$h"
    IFS=','
  done
  IFS="$old_IFS"

  [ "$DRY_RUN" = "true" ] && return 0
  ok "atlas-aci removed from $hosts_csv (.atlas/ left on disk — delete manually if unwanted)"
}

case "$ACTION" in
  install) main_install ;;
  remove)  main_remove ;;
  *)       exit_usage "Unknown action: $ACTION" ;;
esac
