#!/usr/bin/env bash
# eidolons init — bootstrap a project with Eidolons
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

PRESET=""
MEMBERS=""
HOSTS=""
HOSTS_EXPLICIT=false
SHARED_DISPATCH=""
NON_INTERACTIVE=false
FORCE=false

usage() {
  cat <<EOF
eidolons init — initialize a project with Eidolons

Usage: eidolons init [OPTIONS]

Options:
  --preset NAME            Use a named preset from the roster (minimal, pipeline, full, ...)
                           Run 'eidolons list --presets' to see all.
  --members LIST           Comma-separated list of Eidolon names.
                           Mutually exclusive with --preset.
  --hosts LIST             Comma-separated: claude-code,copilot,cursor,opencode,all
                           Required in --non-interactive mode when no hosts are auto-detected.
                           Interactive mode will prompt if omitted and detection finds nothing.
  --shared-dispatch        Compose root AGENTS.md / CLAUDE.md / .github/copilot-instructions.md
                           with marker-bounded per-Eidolon sections (opt-in).
  --no-shared-dispatch     Skip root dispatch files (default). Per-vendor agent/skill files
                           under .claude/, .github/, .cursor/, .opencode/ remain self-sufficient.
  --force                  Overwrite existing eidolons.yaml without prompting.
  --non-interactive        Fail on any prompt. Requires --preset or --members and explicit
                           --hosts (no broadcast when detection finds nothing).
  -h, --help               Show this help

Behavior:
  - Detects which host environments are present in the current project.
  - Interactive: prompts for missing host selection, and whether to compose
    root dispatch files (default: no).
  - Non-interactive: fails if no hosts detected and --hosts not supplied.
  - Writes eidolons.yaml + eidolons.lock, then delegates to 'eidolons sync'.
  - Per-Eidolon installers receive --shared-dispatch / --no-shared-dispatch
    based on the user's choice.

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)               PRESET="$2"; shift 2 ;;
    --members)              MEMBERS="$2"; shift 2 ;;
    --hosts)                HOSTS="$2"; HOSTS_EXPLICIT=true; shift 2 ;;
    --shared-dispatch)      SHARED_DISPATCH="true"; shift ;;
    --no-shared-dispatch)   SHARED_DISPATCH="false"; shift ;;
    --force)                FORCE=true; shift ;;
    --non-interactive)      NON_INTERACTIVE=true; shift ;;
    -h|--help)              usage; exit 0 ;;
    *)                      echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ─── Detect greenfield vs brownfield ──────────────────────────────────────
PROJECT_STATE="greenfield"
if [[ -n "$(ls -A . 2>/dev/null)" ]]; then
  PROJECT_STATE="brownfield"
fi
say "Project state: $PROJECT_STATE ($(pwd))"

# ─── Idempotency check ────────────────────────────────────────────────────
if manifest_exists && [[ "$FORCE" != "true" ]]; then
  warn "eidolons.yaml already exists. Use --force to overwrite, or 'eidolons add/sync' instead."
  exit 1
fi

# ─── Resolve members ──────────────────────────────────────────────────────
resolve_members() {
  if [[ -n "$PRESET" ]]; then
    roster_preset_members "$PRESET" | paste -sd, -
    return
  fi
  if [[ -n "$MEMBERS" ]]; then
    echo "$MEMBERS"
    return
  fi
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    die "No members specified. Use --preset or --members when --non-interactive."
  fi
  # Interactive picker — all listing output goes to stderr so it does not
  # pollute this function's stdout (captured by the caller).
  {
    echo ""
    echo "${BOLD}Available presets:${RESET}"
    yaml_to_json "$ROSTER_FILE" | jq -r '.presets | to_entries[] | "  \(.key) — \(.value.description)"'
    echo ""
    echo "${BOLD}Available Eidolons:${RESET}"
    yaml_to_json "$ROSTER_FILE" | jq -r '.eidolons[] | "  \(.name) — \(.methodology.summary)"'
    echo ""
  } >&2
  local choice=""
  read -rp "Enter preset name, or comma-separated members: " choice || true
  choice="$(echo "$choice" | xargs)"
  [[ -z "$choice" ]] && die "No selection made."
  if roster_presets | grep -Fxq "$choice"; then
    roster_preset_members "$choice" | paste -sd, -
  else
    echo "$choice"
  fi
}

MEMBERS_CSV="$(resolve_members | tr -d '\n' | xargs)"
[[ -z "$MEMBERS_CSV" ]] && die "No members resolved. Aborting."
IFS=',' read -ra MEMBERS_ARR <<< "$MEMBERS_CSV"
(( ${#MEMBERS_ARR[@]} > 0 )) || die "No members resolved. Aborting."
say "Members: ${MEMBERS_ARR[*]}"

# Validate every member exists in the roster
for m in "${MEMBERS_ARR[@]}"; do
  m="$(echo "$m" | xargs)"  # trim
  roster_get "$m" >/dev/null
done

# ─── Resolve hosts ────────────────────────────────────────────────────────
# Policy: never broadcast when no host is detected. Require explicit
# --hosts in non-interactive; prompt interactively otherwise.
if [[ "$HOSTS_EXPLICIT" != "true" ]]; then
  detected="$(detect_hosts | paste -sd, -)"
  if [[ -n "$detected" ]]; then
    HOSTS="$detected"
    info "Detected hosts: $HOSTS"
  else
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
      die "No hosts auto-detected in this project. Pass --hosts LIST explicitly (valid: claude-code, copilot, cursor, opencode, all)."
    fi
    {
      echo ""
      echo "${BOLD}No AI host environments detected in this project.${RESET}"
      echo "Pick which host(s) to wire (comma-separated):"
      echo "  - claude-code"
      echo "  - copilot"
      echo "  - cursor"
      echo "  - opencode"
      echo "  - all (every host above)"
      echo "  - (leave blank to abort)"
      echo ""
    } >&2
    read -rp "Hosts: " HOSTS || true
    HOSTS="$(echo "${HOSTS:-}" | xargs)"
    [[ -z "$HOSTS" ]] && die "No hosts selected. Aborting — specify --hosts explicitly or re-run."
  fi
fi
[[ "$HOSTS" == "all" ]] && HOSTS="claude-code,copilot,cursor,opencode"

# ─── Resolve shared-dispatch preference ───────────────────────────────────
# Opt-in by design. Per-vendor files (.claude/agents/<n>.md, .cursor/rules/<n>.mdc,
# .opencode/agents/<n>.md, .github/instructions/) are self-sufficient for their
# hosts to discover the Eidolon. Root AGENTS.md / CLAUDE.md / copilot-
# instructions.md are a separate composition concern — default off so they don't
# clutter brownfield projects without permission.
if [[ -z "$SHARED_DISPATCH" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    SHARED_DISPATCH="false"
  else
    {
      echo ""
      echo "${BOLD}Compose root dispatch files?${RESET}"
      echo "If yes, each Eidolon will own a marker-bounded section in root"
      echo "  AGENTS.md, CLAUDE.md, and .github/copilot-instructions.md."
      echo "If no, only per-vendor files (.claude/agents/, .cursor/rules/, etc.)"
      echo "  are created — agents remain self-sufficient via host discovery."
      echo ""
    } >&2
    read -rp "Generate shared dispatch files? [y/N] " _reply || true
    if [[ "$_reply" =~ ^[Yy]$ ]]; then
      SHARED_DISPATCH="true"
    else
      SHARED_DISPATCH="false"
    fi
  fi
fi
info "Shared dispatch: $SHARED_DISPATCH"

# ─── Write eidolons.yaml ─────────────────────────────────────────────────
say "Writing $PROJECT_MANIFEST"
{
  echo "# eidolons.yaml — per-project manifest"
  echo "# Generated by eidolons v${EIDOLONS_VERSION:-1.0.0} at $(date -u +%FT%TZ)"
  echo "# Docs: https://github.com/Rynaro/eidolons/blob/main/docs/getting-started.md"
  echo ""
  echo "version: 1"
  echo "hosts:"
  echo "  wire: [$(echo "$HOSTS" | sed 's/,/, /g')]"
  echo "  shared_dispatch: ${SHARED_DISPATCH}"
  echo ""
  echo "members:"
  for m in "${MEMBERS_ARR[@]}"; do
    m="$(echo "$m" | xargs)"
    entry="$(roster_get "$m")"
    latest="$(echo "$entry" | jq -r '.versions.latest')"
    repo="$(echo "$entry" | jq -r '.source.repo')"
    echo "  - name: $m"
    echo "    version: \"^$latest\""
    echo "    source: github:$repo"
  done
  echo ""
  echo "# Optional documentation of the intended pipeline:"
  echo "# composition:"
  echo "#   pipeline: [atlas, spectra, apivr, idg]"
} > "$PROJECT_MANIFEST"

ok "$PROJECT_MANIFEST written"

# ─── Delegate actual install to `eidolons sync` ──────────────────────────
say "Running sync to install members"
exec bash "$SELF_DIR/sync.sh" ${NON_INTERACTIVE:+--non-interactive}
