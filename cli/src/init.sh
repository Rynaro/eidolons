#!/usr/bin/env bash
# eidolons init — bootstrap a project with Eidolons
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/ui/prompt.sh"

PRESET=""
MEMBERS=""
HOSTS=""
HOSTS_EXPLICIT=false
SHARED_DISPATCH=""
NON_INTERACTIVE=false
FORCE=false
QUIET=false
VERBOSE_FLAG=false
STRICT_HOSTS=false

usage() {
  cat <<EOF
eidolons init — initialize a project with Eidolons

Usage: eidolons init [OPTIONS]

Options:
  --preset NAME            Use a named preset from the roster (minimal, pipeline, full, ...)
                           Run 'eidolons list --presets' to see all.
  --members LIST           Comma-separated list of Eidolon names.
                           Mutually exclusive with --preset.
  --hosts LIST             Comma-separated: claude-code,copilot,cursor,opencode,codex,all
                           Required in --non-interactive mode when no hosts are auto-detected.
                           Interactive mode always prompts to confirm — auto-detected hosts
                           become the default applied on Enter. Letter shortcuts accepted:
                           c=claude-code, x=codex, o=copilot, u=cursor, p=opencode, a=all.
                           Combine letters (e.g. 'co' = claude-code+copilot).
  --shared-dispatch        Compose root AGENTS.md / CLAUDE.md / .github/copilot-instructions.md
                           with marker-bounded per-Eidolon sections (opt-in).
  --no-shared-dispatch     Skip root dispatch files (default). Per-vendor agent/skill files
                           under .claude/, .github/, .cursor/, .opencode/ remain self-sufficient.
  --force                  Overwrite existing eidolons.yaml without prompting.
  --non-interactive        Fail on any prompt. Requires --preset or --members and explicit
                           --hosts (no broadcast when detection finds nothing).
  --strict-hosts           Treat per-Eidolon writes for non-selected hosts as a hard
                           error rather than a silent path-pattern prune. Requires
                           per-Eidolon install.manifest.json to annotate `host` per file.
                           Persisted to eidolons.yaml under hosts.strict (default: false).
  -h, --help               Show this help

Behavior:
  - Detects which host environments are present in the current project.
  - Interactive: always confirms host selection (Enter accepts the detected
    default, letters override), and asks whether to compose root dispatch
    files (default: no).
  - Non-interactive: auto-applies detection when found, otherwise fails
    unless --hosts was supplied.
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
    --quiet)                QUIET=true; shift ;;
    --verbose)              VERBOSE_FLAG=true; shift ;;
    --strict-hosts)         STRICT_HOSTS=true; shift ;;
    -h|--help)              usage; exit 0 ;;
    *)                      echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ─── Verbosity tier ──────────────────────────────────────────────────────
# Honour env vars first, then CLI flags. Flags win over env vars.
if [[ "$VERBOSE_FLAG" == "true" ]] || [[ "${EIDOLONS_VERBOSE:-0}" == "1" ]]; then
  VERBOSITY="verbose"
elif [[ "$QUIET" == "true" ]] || [[ "${EIDOLONS_QUIET:-0}" == "1" ]]; then
  VERBOSITY="quiet"
else
  VERBOSITY="default"
fi
export VERBOSITY

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
  # pollute this function's stdout (captured by the caller). ui_section
  # already writes to stderr.
  ui_section "Available presets"
  yaml_to_json "$ROSTER_FILE" | jq -r '.presets | to_entries[] | "  \(.key) — \(.value.description)"' >&2
  ui_section "Available Eidolons"
  yaml_to_json "$ROSTER_FILE" | jq -r '.eidolons[] | "  \(.name) — \(.methodology.summary)"' >&2
  echo "" >&2
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
# Policy: never silently apply auto-detection in interactive mode — the
# user gets the last word via ui_pick_hosts (Enter accepts the detected
# default). Non-interactive mode preserves auto-application so CI flows
# that rely on detection (see init.bats codex tests) keep working.
if [[ "$HOSTS_EXPLICIT" != "true" ]]; then
  detected="$(detect_hosts | paste -sd, -)"
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    if [[ -n "$detected" ]]; then
      HOSTS="$detected"
      info "Detected hosts: $HOSTS"
    else
      die "No hosts auto-detected in this project. Pass --hosts LIST explicitly (valid: claude-code, copilot, cursor, opencode, codex, all)."
    fi
  else
    if [[ -n "$detected" ]]; then
      info "Detected hosts: $detected (press Enter to accept, or override below)"
    else
      {
        echo ""
        echo "${BOLD}No AI host environments detected in this project.${RESET}"
        echo "Pick which host(s) to wire. Each choice will create the folders"
        echo "it needs in this project if they don't exist:"
        echo ""
        echo "  - claude-code  → creates .claude/agents/  and .claude/skills/"
        echo "  - copilot      → creates .github/instructions/"
        echo "  - cursor       → creates .cursor/rules/"
        echo "  - opencode     → creates .opencode/agents/"
        echo "  - codex        → creates AGENTS.md (root) and .codex/agents/"
        echo "  - all          (every host above)"
        echo "  - (leave blank to abort)"
      } >&2
    fi
    HOSTS="$(ui_pick_hosts "$detected")"
    HOSTS="$(echo "${HOSTS:-}" | xargs)"
    [[ -z "$HOSTS" ]] && die "No hosts selected. Aborting — specify --hosts explicitly or re-run."
  fi
fi
[[ "$HOSTS" == "all" ]] && HOSTS="claude-code,copilot,cursor,opencode,codex"

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
    if ui_confirm "Generate shared dispatch files?" default-n; then
      SHARED_DISPATCH="true"
    else
      SHARED_DISPATCH="false"
    fi
  fi
fi
info "Shared dispatch: $SHARED_DISPATCH"

# ─── Resolve pointer_targets ──────────────────────────────────────────────
# Determines which vendor files receive the EIDOLONS dispatch-pointer and
# cortex block. Prompt flow (D2, SPEC §3.3):
#   1. If NON_INTERACTIVE → derive from hosts.wire (v1.6.0 default).
#   2. Otherwise:
#      a. Detect vendor files already on disk.
#      b. AGENTS-first short-circuit: if AGENTS.md detected, offer
#         exclusivity prompt (AGENTS.md only → skip ui_pick_vendors).
#      c. Multi-vendor ui_pick_vendors when |candidates| > 1.
#      d. Single candidate auto-selects.
#
# When re-running with --force on a manifest that already has pointer_targets,
# the existing value becomes the preselected default (D7).
POINTER_TARGETS=""

# Read existing pointer_targets from manifest as reprompt default (D7).
_existing_pt=""
if manifest_exists && [[ "$FORCE" == "true" ]]; then
  _existing_pt="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
    | jq -r '.hosts.pointer_targets // [] | join(",")' 2>/dev/null || true)"
fi

_host_derived_csv="$(derive_pointer_targets_from_hosts "$HOSTS")"
_detected_vendors="$(detect_vendor_files_on_disk | tr '\n' ',' | sed 's/,$//')"

if [[ "$NON_INTERACTIVE" == "true" ]]; then
  POINTER_TARGETS="$_host_derived_csv"
else
  # Compute candidates: union of detected on-disk vendors and host-derived.
  _candidates=""
  for _cv in CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md; do
    _in_detected=false; _in_derived=false
    case ",$_detected_vendors," in *",$_cv,"*) _in_detected=true ;; esac
    case ",$_host_derived_csv," in *",$_cv,"*) _in_derived=true ;; esac
    if [[ "$_in_detected" == "true" ]] || [[ "$_in_derived" == "true" ]]; then
      if [[ -z "$_candidates" ]]; then _candidates="$_cv"; else _candidates="$_candidates,$_cv"; fi
    fi
  done

  _default_pt="${_existing_pt:-$_host_derived_csv}"

  # Step (b): AGENTS-first exclusivity short-circuit.
  _agents_exclusive=false
  case ",$_detected_vendors," in
    *",AGENTS.md,"*)
      {
        echo ""
        echo "${BOLD}AGENTS.md is present in this project.${RESET}"
        echo "Codex/opencode treat AGENTS.md as the canonical surface."
        echo "Answering YES restricts eidolons to AGENTS.md only — CLAUDE.md and"
        echo "other vendor files will not be created or modified."
        echo ""
      } >&2
      if ui_confirm "AGENTS.md detected — is AGENTS.md the only canonical agent-instructions file you want eidolons to manage?" default-n; then
        POINTER_TARGETS="AGENTS.md"
        _agents_exclusive=true
      fi
      ;;
  esac

  if [[ "$_agents_exclusive" != "true" ]]; then
    # Count candidates (comma-count + 1).
    _cand_count=1
    case "$_candidates" in
      "") _cand_count=0 ;;
      *,*) _cand_count=2 ;;  # at least 2; exact count not needed — we just need >1
    esac

    if [[ "$_cand_count" -gt 1 ]]; then
      {
        echo ""
        echo "${BOLD}Pick vendor file(s) to receive the EIDOLONS pointer + cortex block.${RESET}"
        echo "Default is all auto-detected/host-derived files."
        echo "Letters: c=CLAUDE.md, a=AGENTS.md, g=GEMINI.md,"
        echo "         i=.github/copilot-instructions.md, A=all."
        echo ""
      } >&2
      POINTER_TARGETS="$(ui_pick_vendors "$_default_pt" "$_candidates")"
      POINTER_TARGETS="$(echo "$POINTER_TARGETS" | tr '\n' ',' | sed 's/,$//')"
      if [[ -z "$POINTER_TARGETS" ]]; then
        die "No pointer targets selected. Aborting — specify hosts.pointer_targets in eidolons.yaml or re-run."
      fi
    elif [[ "$_cand_count" -eq 1 ]]; then
      POINTER_TARGETS="$_candidates"
    else
      # No candidates at all — fall back to host-derived (may be empty).
      POINTER_TARGETS="$_host_derived_csv"
    fi
  fi
fi

unset _existing_pt _host_derived_csv _detected_vendors _candidates _default_pt _agents_exclusive _cand_count _cv _in_detected _in_derived

info "Pointer targets: ${POINTER_TARGETS:-(none)}"

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
  echo "  strict: ${STRICT_HOSTS}"
  if [[ -n "$POINTER_TARGETS" ]]; then
    echo "  pointer_targets: [$(echo "$POINTER_TARGETS" | sed 's/,/, /g')]"
  fi
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

# ─── .gitignore policy ───────────────────────────────────────────────────
# Mark the bulky per-Eidolon `.eidolons/<name>/` artefacts as recreatable
# by sync; keep the small nexus-owned cortex + harness marker in VCS.
# No-op when not a git repo. See lib.sh::apply_eidolons_gitignore.
apply_eidolons_gitignore

# ─── Delegate actual install to `eidolons sync` ──────────────────────────
# init already confirmed the host + dispatch choices interactively — skip
# sync's pre-install preview to avoid double-prompting. Non-interactive
# mode inherits the same behaviour. --strict-hosts is forwarded only when
# the flag was set explicitly; otherwise sync reads it from the manifest.
SYNC_STRICT_FLAG=""
[[ "$STRICT_HOSTS" == "true" ]] && SYNC_STRICT_FLAG="--strict-hosts"
say "Running sync to install members"
# shellcheck disable=SC2046
exec bash "$SELF_DIR/sync.sh" \
  ${NON_INTERACTIVE:+--non-interactive} \
  --yes \
  ${SYNC_STRICT_FLAG} \
  $([ "$VERBOSITY" = "quiet" ] && echo --quiet) \
  $([ "$VERBOSITY" = "verbose" ] && echo --verbose)
