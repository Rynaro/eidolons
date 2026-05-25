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
RE_DERIVE=false
POINTER_TARGETS_ARG=""
MULTI_POINTER=false
MULTI_POINTER_EXPLICIT=false
_MP_YES_SEEN=false
_MP_NO_SEEN=false

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
  --re-derive              Re-derive hosts.pointer_targets in the existing
                           eidolons.yaml using the round-4 precedence rules.
                           Preserves all other manifest fields. Requires an
                           existing eidolons.yaml (dies if absent). Used to
                           migrate v1.7.0 projects to round-4 semantics.
  --pointer-targets=CSV    Explicit pointer_targets override (comma-separated,
                           e.g. CLAUDE.md or AGENTS.md,CLAUDE.md). Bypasses
                           AGENTS-precedence derivation. Warns when AGENTS.md
                           exists on disk but is not in the supplied set.
  --multi-pointer          When AGENTS-precedence triggers, additionally
                           wire host-derived vendor files (CLAUDE.md, GEMINI.md,
                           .github/copilot-instructions.md). Default ON; pass
                           --no-multi-pointer to opt out.
  --no-multi-pointer       Make AGENTS.md the sole pointer target under
                           AGENTS-precedence. Wired vendor files (CLAUDE.md,
                           GEMINI.md, .github/copilot-instructions.md) will
                           be emptied of Eidolon markers during compose.
                           Mutually exclusive with --multi-pointer.
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
    --re-derive)            RE_DERIVE=true; FORCE=true; shift ;;
    --pointer-targets)      POINTER_TARGETS_ARG="$2"; shift 2 ;;
    --pointer-targets=*)    POINTER_TARGETS_ARG="${1#*=}"; shift ;;
    --multi-pointer)        MULTI_POINTER=true; MULTI_POINTER_EXPLICIT=true; _MP_YES_SEEN=true; shift ;;
    --no-multi-pointer)     MULTI_POINTER=false; MULTI_POINTER_EXPLICIT=true; _MP_NO_SEEN=true; shift ;;
    -h|--help)              usage; exit 0 ;;
    *)                      echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Mutual exclusion: --multi-pointer and --no-multi-pointer are mutually exclusive.
if [[ "$_MP_YES_SEEN" == "true" ]] && [[ "$_MP_NO_SEEN" == "true" ]]; then
  die "--multi-pointer and --no-multi-pointer are mutually exclusive."
fi
unset _MP_YES_SEEN _MP_NO_SEEN

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

# ─── --re-derive: surgical pointer_targets migration (D10) ───────────────
# This flag re-runs derivation only, preserving all other manifest fields.
# Must execute BEFORE the normal init flow (no preset resolution, no sync).
if [[ "$RE_DERIVE" == "true" ]]; then
  if ! manifest_exists; then
    die "eidolons init --re-derive requires an existing eidolons.yaml — run 'eidolons init' first."
  fi

  # Read fields we need from the existing manifest.
  _rd_manifest_json="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null)" || \
    die "eidolons init --re-derive: cannot parse existing eidolons.yaml"
  _rd_hosts_csv="$(printf '%s\n' "$_rd_manifest_json" \
    | jq -r '.hosts.wire // [] | join(",")' 2>/dev/null || true)"
  _rd_shared_dispatch="$(printf '%s\n' "$_rd_manifest_json" \
    | jq -r '.hosts.shared_dispatch // "false"' 2>/dev/null || true)"

  # Determine new pointer_targets.
  _rd_host_derived="$(derive_pointer_targets_from_hosts "$_rd_hosts_csv")"
  _rd_new_pt=""

  if [[ -n "$POINTER_TARGETS_ARG" ]]; then
    # Explicit override path.
    _rd_new_pt="$(_validate_pointer_targets_csv "$POINTER_TARGETS_ARG")"
    case ",$_rd_new_pt," in
      *",AGENTS.md,"*) : ;;
      *)
        if [[ -f "AGENTS.md" ]]; then
          warn "--pointer-targets does not include AGENTS.md but AGENTS.md exists on disk."
          warn "Installers may write to AGENTS.md anyway under shared_dispatch=true."
          warn "Consider 'eidolons init --re-derive' to align with AGENTS-precedence."
        fi
        ;;
    esac
  elif detect_agents_precedence_trigger "$_rd_hosts_csv" "$_rd_shared_dispatch"; then
    _rd_new_pt="AGENTS.md"
    # R5-D1: re-derive uses default-Y for multi-pointer unless --no-multi-pointer
    # was explicit on this invocation. (No TTY prompt in --re-derive; it's a
    # non-interactive migration tool by convention.)
    if [[ "$MULTI_POINTER" == "true" ]] || [[ "$MULTI_POINTER_EXPLICIT" != "true" ]]; then
      _rd_new_pt="$(_csv_union "AGENTS.md" "$_rd_host_derived")"
    fi
    # If --no-multi-pointer was explicit: leave _rd_new_pt=AGENTS.md only.
  else
    _rd_new_pt="$_rd_host_derived"
  fi

  # Rewrite only the pointer_targets line (atomic via tmp file).
  _rd_tmpfile="${PROJECT_MANIFEST}.re-derive.tmp"
  if [[ -n "$_rd_new_pt" ]]; then
    _rd_pt_yaml="  pointer_targets: [$(printf '%s\n' "$_rd_new_pt" | sed 's/,/, /g')]"
  else
    _rd_pt_yaml=""
  fi

  # Use awk to replace or remove the pointer_targets line.
  awk -v new_pt="$_rd_pt_yaml" '
    /^[[:space:]]*pointer_targets:/ {
      if (new_pt != "") { print new_pt }
      next
    }
    { print }
  ' "$PROJECT_MANIFEST" > "$_rd_tmpfile"

  # If pointer_targets line was absent and we need to add it, insert after strict: line.
  if [[ -n "$_rd_pt_yaml" ]] && ! grep -q 'pointer_targets:' "$_rd_tmpfile"; then
    awk -v new_pt="$_rd_pt_yaml" '
      /^[[:space:]]*strict:/ { print; print new_pt; next }
      { print }
    ' "$_rd_tmpfile" > "${_rd_tmpfile}.2" && mv "${_rd_tmpfile}.2" "$_rd_tmpfile"
  fi

  mv "$_rd_tmpfile" "$PROJECT_MANIFEST"
  unset _rd_manifest_json _rd_hosts_csv _rd_shared_dispatch _rd_host_derived _rd_new_pt _rd_tmpfile _rd_pt_yaml

  ok "Updated hosts.pointer_targets in eidolons.yaml — re-run 'eidolons sync' to apply."
  info "Orphan dispatch-pointer block(s) may remain in previously-targeted vendor files (e.g. CLAUDE.md). They correctly point to ./EIDOLONS.md and are harmless. Delete the <!-- eidolon:dispatch-pointer start --> ... end --> markers and the file body between them to remove."
  exit 0
fi

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

# ─── Resolve pointer_targets (round 4 deterministic derivation) ──────────
# D1/D4 (SPEC INIT-R4): Replace v1.7.0 exclusivity prompt with deterministic
# AGENTS-precedence rule. Three triggers: AGENTS.md on disk, shared_dispatch=true,
# or codex in hosts.wire → pointer_targets=[AGENTS.md].
# Flags: --pointer-targets=CSV overrides; --multi-pointer extends with host-derived.
# Interactive: TTY prompt for --multi-pointer when flag not explicitly passed.
POINTER_TARGETS=""
_host_derived_csv="$(derive_pointer_targets_from_hosts "$HOSTS")"

if [[ -n "$POINTER_TARGETS_ARG" ]]; then
  # Explicit override path. Validate CSV and emit foot-gun warn if needed.
  POINTER_TARGETS="$(_validate_pointer_targets_csv "$POINTER_TARGETS_ARG")"
  case ",$POINTER_TARGETS," in
    *",AGENTS.md,"*) : ;;
    *)
      if [[ -f "AGENTS.md" ]]; then
        warn "--pointer-targets does not include AGENTS.md but AGENTS.md exists on disk."
        warn "Installers may write to AGENTS.md anyway under shared_dispatch=true."
        warn "Consider 'eidolons init --re-derive' to align with AGENTS-precedence."
      fi
      ;;
  esac
  # Explicit override silences Case A and Case B messages.
elif detect_agents_precedence_trigger "$HOSTS" "$SHARED_DISPATCH"; then
  # AGENTS-precedence triggered. Default behaviour (R5-D1): pointer_targets starts
  # at AGENTS.md and is UNIONed with host-derived wired vendor files unless the
  # user explicitly opted out via --no-multi-pointer.
  POINTER_TARGETS="AGENTS.md"

  if [[ "$MULTI_POINTER_EXPLICIT" == "true" ]]; then
    # Honour the explicit choice (either --multi-pointer or --no-multi-pointer).
    if [[ "$MULTI_POINTER" == "true" ]]; then
      POINTER_TARGETS="$(_csv_union "AGENTS.md" "$_host_derived_csv")"
    fi
    # --no-multi-pointer path: leave POINTER_TARGETS=AGENTS.md (no union).
  elif [[ "$NON_INTERACTIVE" == "true" ]]; then
    # Non-interactive default flip (R5-D1): union by default.
    POINTER_TARGETS="$(_csv_union "AGENTS.md" "$_host_derived_csv")"
  else
    # Interactive TTY prompt fallback. Default-Y (R5-D1).
    {
      echo ""
      echo "AGENTS.md will be the canonical pointer surface (round-4 AGENTS-precedence)."
      echo "By default, eidolons mirrors the dispatch-pointer + cortex block to all wired"
      echo "host files (CLAUDE.md, GEMINI.md, .github/copilot-instructions.md) so every"
      echo "wired LLM redirects to ./EIDOLONS.md. Pass --no-multi-pointer to make"
      echo "AGENTS.md the sole pointer (other vendor files will be emptied)."
      echo ""
    } >&2
    if ui_confirm "Mirror dispatch-pointer to all wired host files? (recommended)" default-y; then
      POINTER_TARGETS="$(_csv_union "AGENTS.md" "$_host_derived_csv")"
    fi
  fi
  # Emit Case A or Case B message (R4-2) — after POINTER_TARGETS is final.
  case ",$HOSTS," in
    *",codex,"*)
      {
        echo ""
        printf '%bcodex detected in hosts.wire%b — AGENTS.md is canonical pointer surface (EIIS §4.1.0).\n' \
          "${BOLD}" "${RESET}"
        echo "Pass --no-multi-pointer to make AGENTS.md the sole pointer."
        echo ""
      } >&2
      ;;
    *)
      {
        echo ""
        printf '%bAGENTS.md will be the canonical pointer surface%b (AGENTS.md outranks host-specific files in modern LLM hosts).\n' \
          "${BOLD}" "${RESET}"
        echo "By default, all wired host files mirror the dispatch-pointer. Pass --no-multi-pointer to opt out."
        echo ""
      } >&2
      ;;
  esac
else
  # No AGENTS-precedence trigger. Greenfield / non-codex / no AGENTS.md / no shared_dispatch.
  POINTER_TARGETS="$_host_derived_csv"
fi

unset _host_derived_csv

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
