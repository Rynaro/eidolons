#!/usr/bin/env bash
# eidolons sync — install/update Eidolons to match eidolons.yaml
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/ui/prompt.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/ui/card.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_host_prune.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_eidolons_md.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp_wiring.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_model_resolve.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_model_wiring.sh"

NON_INTERACTIVE=false
DRY_RUN=false
SKIP_PREVIEW=false
QUIET=false
VERBOSE_FLAG=false
STRICT_HOSTS_CLI=""   # tri-state: "" (use manifest), "true" or "false" (override)

usage() {
  cat <<EOF
eidolons sync — install/update Eidolons to match eidolons.yaml

Usage: eidolons sync [OPTIONS]

Options:
  --non-interactive   Fail on prompts (also skips the pre-install preview)
  --dry-run           Show what would be done without touching disk
  --yes, -y           Skip the pre-install preview confirmation (auto-approve)
  --quiet             Show only the party roster card (suppress per-member output)
  --verbose           Print all log lines plus new cards (debug tier)
  --strict-hosts      Hard-fail if a per-Eidolon installer wrote a vendor file
                      without a manifest `host` annotation. Overrides
                      hosts.strict in eidolons.yaml for this run.
  --no-strict-hosts   Disable strict mode for this run (override manifest).
  -h, --help          Show this help

Behavior:
  - Reads eidolons.yaml
  - In interactive mode, shows a pre-install preview of every path the run
    will create, then asks for confirmation. --yes skips the prompt.
  - For each member: fetches Eidolon repo, runs its install.sh with appropriate --hosts
  - Aggregates install.manifest.json from each member into eidolons.lock
  - Idempotent: safe to run repeatedly
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=true; SKIP_PREVIEW=true; shift ;;
    --dry-run)         DRY_RUN=true; shift ;;
    --yes|-y)          SKIP_PREVIEW=true; shift ;;
    --quiet)           QUIET=true; shift ;;
    --verbose)         VERBOSE_FLAG=true; shift ;;
    --strict-hosts)    STRICT_HOSTS_CLI=true; shift ;;
    --no-strict-hosts) STRICT_HOSTS_CLI=false; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# ─── Verbosity tier ──────────────────────────────────────────────────────
# VERBOSITY may already be set by init.sh (which exec's into sync). CLI
# flags on sync itself take precedence when called directly.
if [[ "$VERBOSE_FLAG" == "true" ]] || [[ "${EIDOLONS_VERBOSE:-0}" == "1" ]]; then
  VERBOSITY="verbose"
elif [[ "$QUIET" == "true" ]] || [[ "${EIDOLONS_QUIET:-0}" == "1" ]]; then
  VERBOSITY="quiet"
elif [[ -z "${VERBOSITY:-}" ]]; then
  VERBOSITY="default"
fi
export VERBOSITY

manifest_exists || die "No eidolons.yaml found. Run 'eidolons init' first."

# Refresh the nexus cache before reading the roster so version lookups always
# see the latest published Eidolon versions.  Skipped when EIDOLONS_NEXUS is
# set (local-checkout / test mode) or EIDOLONS_SKIP_REFRESH=1 (offline-first).
nexus_refresh

MANIFEST_JSON="$(yaml_to_json "$PROJECT_MANIFEST")"
HOSTS_CSV="$(echo "$MANIFEST_JSON" | jq -r '.hosts.wire | join(",")')"
# Default shared_dispatch to false when the key is absent (pre-v1.2 manifests).
SHARED_DISPATCH="$(echo "$MANIFEST_JSON" | jq -r '.hosts.shared_dispatch // false')"
# Default hosts.strict to false when the key is absent (pre-PR-I2 manifests).
STRICT_HOSTS_MANIFEST="$(echo "$MANIFEST_JSON" | jq -r '.hosts.strict // false')"
# CLI flag overrides manifest. Tri-state: "" → use manifest; "true"/"false" → override.
if [[ -n "$STRICT_HOSTS_CLI" ]]; then
  STRICT_HOSTS="$STRICT_HOSTS_CLI"
else
  STRICT_HOSTS="$STRICT_HOSTS_MANIFEST"
fi
MEMBERS_JSON="$(echo "$MANIFEST_JSON" | jq -c '.members[]')"

# ─── Resolve pointer_targets ─────────────────────────────────────────────
# pointer_targets drives compose_eidolons_md sources, apply_dispatch_pointers,
# and cortex injection in this sync run.
# Priority: manifest hosts.pointer_targets → derive from hosts.wire.
# When empty or absent, fall back to derive_pointer_targets_from_hosts.
POINTER_TARGETS_CSV="$(echo "$MANIFEST_JSON" | jq -r '.hosts.pointer_targets // [] | join(",")' 2>/dev/null || true)"
if [[ -z "$POINTER_TARGETS_CSV" ]]; then
  POINTER_TARGETS_CSV="$(derive_pointer_targets_from_hosts "$HOSTS_CSV")"
fi
# Validate pointer_targets against the closed set; warn or die per strict mode.
_valid_targets=""
_invalid_found=false
for _pt in $(echo "$POINTER_TARGETS_CSV" | tr ',' ' '); do
  [[ -z "$_pt" ]] && continue
  case "$_pt" in
    CLAUDE.md|AGENTS.md|GEMINI.md|.github/copilot-instructions.md)
      if [[ -z "$_valid_targets" ]]; then _valid_targets="$_pt"; else _valid_targets="$_valid_targets,$_pt"; fi
      ;;
    *)
      _invalid_found=true
      if [[ "$STRICT_HOSTS" == "true" ]]; then
        die "hosts.pointer_targets contains unknown path '$_pt' (hosts.strict=true)"
      else
        warn "hosts.pointer_targets contains unknown path '$_pt' — skipping"
      fi
      ;;
  esac
done
POINTER_TARGETS_CSV="$_valid_targets"
unset _valid_targets _invalid_found _pt

info "Pointer targets: ${POINTER_TARGETS_CSV:-(none, derived from hosts.wire)}"

# ─── Round-4 sync drift warning (R4-2) ────────────────────────────────────
# Fires when AGENTS.md exists on disk AND has at least one Eidolon content
# marker block (excluding the round-3 dispatch-pointer block) AND AGENTS.md
# is NOT in the active pointer_targets set.
# Remediation: 'eidolons init --re-derive'
_drift_detected=false
if [[ -f "AGENTS.md" ]]; then
  case ",$POINTER_TARGETS_CSV," in
    *",AGENTS.md,"*) : ;;  # AGENTS.md already targeted; no drift
    *)
      # Look for any eidolon:<name> start marker, excluding dispatch-pointer.
      # Two-grep approach: first confirm any marker exists, then confirm at least
      # one non-dispatch-pointer marker exists.
      if grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' "AGENTS.md" 2>/dev/null; then
        if grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' "AGENTS.md" 2>/dev/null \
           | grep -vqE 'eidolon:dispatch-pointer'; then
          _drift_detected=true
        fi
      fi
      ;;
  esac
fi
if [[ "$_drift_detected" == "true" ]]; then
  warn "AGENTS.md exists with Eidolon markers but isn't in pointer_targets. Run 'eidolons init --re-derive' to consolidate."
fi
unset _drift_detected

# Strict-mode violations collected across all per-member loops; checked at
# end-of-sync so the user sees every offending Eidolon at once.
_STRICT_VIOLATIONS=0

# ─── DETECT stage ────────────────────────────────────────────────────────
[[ "${VERBOSITY:-default}" != "quiet" ]] && ui_section "DETECT  host environments"
say "Syncing project to $PROJECT_MANIFEST"
info "Hosts: $HOSTS_CSV"
info "Shared dispatch: $SHARED_DISPATCH"

# ─── codex + --no-shared-dispatch override (T.12) ────────────────────────
# AGENTS.md is Codex's primary instruction surface — see
# https://developers.openai.com/codex/guides/agents-md. When the manifest
# wires codex but persists shared_dispatch: false, override at execution
# time and warn. eidolons.yaml continues to record the user's intent
# faithfully so the flag still applies if codex is later removed from wire.
EFFECTIVE_SHARED_DISPATCH="$SHARED_DISPATCH"
if [[ ",$HOSTS_CSV," == *",codex,"* ]] && [[ "$SHARED_DISPATCH" != "true" ]]; then
  warn "--no-shared-dispatch ignored for hosts.wire containing codex; AGENTS.md is Codex's primary instruction surface."
  EFFECTIVE_SHARED_DISPATCH="true"
fi

# ─── Pre-install preview ─────────────────────────────────────────────────
# Shows every directory the run is about to create (per-Eidolon install
# target + per-host vendor folders the user picked). Respects --yes /
# --non-interactive. Bypassed on --dry-run since the real dry-run below
# already shows equivalent output.
if [[ "$SKIP_PREVIEW" != "true" && "$DRY_RUN" != "true" ]]; then
  preview_paths=()
  while read -r _member; do
    _name="$(echo "$_member" | jq -r '.name')"
    preview_paths+=("./.eidolons/${_name}/")
  done <<< "$MEMBERS_JSON"
  IFS=',' read -ra _host_arr <<< "$HOSTS_CSV"
  for _h in "${_host_arr[@]}"; do
    case "$_h" in
      claude-code)
        [[ -d ".claude/agents"       ]] || preview_paths+=(".claude/agents/")
        [[ -d ".claude/skills"       ]] || preview_paths+=(".claude/skills/")
        ;;
      copilot)
        [[ -d ".github/instructions" ]] || preview_paths+=(".github/instructions/")
        ;;
      cursor)
        [[ -d ".cursor/rules"        ]] || preview_paths+=(".cursor/rules/")
        ;;
      opencode)
        [[ -d ".opencode/agents"     ]] || preview_paths+=(".opencode/agents/")
        ;;
      codex)
        # Codex wires both a root AGENTS.md (shared dispatch) AND a per-
        # Eidolon subagent file under .codex/agents/<name>.md. AGENTS.md
        # is shown unconditionally because EFFECTIVE_SHARED_DISPATCH is
        # always true when codex is wired (T.12 override).
        if [[ -f "AGENTS.md" ]]; then
          preview_paths+=("AGENTS.md  (updated in place)")
        else
          preview_paths+=("AGENTS.md  (new file)")
        fi
        [[ -d ".codex/agents" ]] || preview_paths+=(".codex/agents/")
        while read -r _m; do
          _mn="$(echo "$_m" | jq -r '.name')"
          preview_paths+=(".codex/agents/${_mn}.md")
        done <<< "$MEMBERS_JSON"
        ;;
    esac
  done
  if [[ "$EFFECTIVE_SHARED_DISPATCH" == "true" ]]; then
    for _f in CLAUDE.md .github/copilot-instructions.md; do
      [[ -f "$_f" ]] || preview_paths+=("$_f  (new file)")
    done
    # AGENTS.md is previewed by the codex branch above when codex is wired;
    # otherwise add it here for copilot-only shared-dispatch projects.
    if [[ ",$HOSTS_CSV," != *",codex,"* ]]; then
      [[ -f "AGENTS.md" ]] || preview_paths+=("AGENTS.md  (new file)")
    fi
  fi
  ui_section_out "About to create / modify"
  for _p in "${preview_paths[@]}"; do
    echo "  - $_p"
  done
  echo ""
  if ! ui_confirm "Proceed?" default-y; then
    die "Sync aborted by user."
  fi
fi

# ─── Lock file assembly ──────────────────────────────────────────────────
# Snapshot previous lockfile's name@version set BEFORE we rewrite it.
# Used to decide whether each member is a fresh install (→ ACQUIRED card)
# or an idempotent re-run (→ no card). One newline-separated entry per
# member: "atlas@4.2.1". Empty when no prior lockfile exists.
_PREV_LOCK_MEMBERS=""
if [[ -f "$PROJECT_LOCK" ]]; then
  _PREV_LOCK_MEMBERS="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r '(.members // []) | map(.name + "@" + .version) | .[]' 2>/dev/null \
    || true)"
fi

LOCK_TMP="$(mktemp)"
cat > "$LOCK_TMP" <<EOF
# eidolons.lock — auto-generated by 'eidolons sync'. Commit to VCS.
generated_at: "$(date -u +%FT%TZ)"
eidolons_cli_version: "${EIDOLONS_VERSION:-1.0.0}"
nexus_commit: "$(git -C "$NEXUS" rev-parse HEAD 2>/dev/null || echo unknown)"
members:
EOF

# ─── Count members for progress display ──────────────────────────────────
_member_total=0
while IFS= read -r _mc; do
  [[ -n "$_mc" ]] && _member_total=$((_member_total + 1))
done <<< "$MEMBERS_JSON"
_member_idx=0
_member_new_count=0
_sync_has_failure=false

# ─── FETCH stage ─────────────────────────────────────────────────────────
[[ "${VERBOSITY:-default}" == "verbose" ]] && ui_section "FETCH  $_member_total members"

# ─── Per-member install ──────────────────────────────────────────────────
while read -r member; do
  name="$(echo "$member" | jq -r '.name')"
  version_spec="$(echo "$member" | jq -r '.version')"
  # Resolve the version constraint (^X.Y.Z / ~X.Y.Z / bare X.Y.Z) to a
  # concrete version from the roster's known release set.
  version="$(resolve_version_constraint "$name" "$version_spec")"

  entry="$(roster_get "$name")"
  target="./.eidolons/$name"
  _member_idx=$((_member_idx + 1))

  say "Installing $name@$version → $target"

  if [[ "$DRY_RUN" == "true" ]]; then
    # Dry-run always prints its plan regardless of verbosity tier.
    printf '%s%s%s   [dry-run] would fetch and install %s@%s\n' \
      "${UI_INFO}" "${GLYPH_INFO}" "${RESET}" "$name" "$version" >&2
    continue
  fi

  clone_dir="$(fetch_eidolon "$name" "$version")"
  ui_progress_line "$_member_idx" "$_member_total" "$name@$version" "fetched"

  # EIIS sanity check (warn only; per-Eidolon install.sh is still the source of truth)
  eiis_check "$clone_dir" "$name" || true

  # ECL version-check (warn only in v1.0; promotion path: v1.1 — fail on mismatch beyond ±1 minor).
  # Compares the ECL_VERSION file shipped in the Eidolon repo (single-line, e.g. "1.0")
  # against the roster's declared comm.envelope_version for this member.
  # If the file is absent, skip silently — live Eidolons may not yet ship ECL_VERSION.
  ecl_file="$clone_dir/ECL_VERSION"
  if [[ -f "$ecl_file" ]]; then
    ecl_repo_ver="$(tr -d '[:space:]' < "$ecl_file")"
    ecl_roster_ver="$(echo "$entry" | jq -r '.comm.envelope_version // empty')"
    if [[ -n "$ecl_roster_ver" && "$ecl_repo_ver" != "$ecl_roster_ver" ]]; then
      warn "$name ECL version mismatch: repo declares $ecl_repo_ver, roster expects $ecl_roster_ver"
    fi
  fi

  # ─── INSTALL stage banner (per member) ──────────────────────────────────
  [[ "${VERBOSITY:-default}" == "verbose" ]] && \
    ui_section "INSTALL  member $_member_idx of $_member_total — $name"

  # Detect whether this member is a fresh install vs idempotent re-run.
  # We compare against the previous lockfile's name@version set (snapshot
  # taken before LOCK_TMP was created). If this name@version was already
  # in the lock, the ACQUIRED card is suppressed.
  _is_fresh_install=true
  if [[ -n "$_PREV_LOCK_MEMBERS" ]] && \
     printf '%s\n' "$_PREV_LOCK_MEMBERS" | grep -Fxq "$name@$version"; then
    _is_fresh_install=false
  fi

  # Delegate to the Eidolon's own install.sh (EIIS §3 contract).
  if [[ ! -x "$clone_dir/install.sh" ]]; then
    warn "$name has no executable install.sh — EIIS v1.0 contract violated. Skipping."
    ui_failed_card "$name" "no executable install.sh (EIIS contract violated)"
    _sync_has_failure=true
    continue
  fi

  # Shared-dispatch flag — tells the per-Eidolon installer whether to compose
  # root AGENTS.md / CLAUDE.md / copilot-instructions.md or skip them.
  # Flag-compat shim: only pass the flag if the installer declares support.
  # Older per-Eidolon installers (pre-v1.x.3) don't recognise it and exit 2
  # on any unknown arg — we refuse to proceed in that case when the user's
  # intent (shared_dispatch=false) would silently conflict with the old
  # default (compose everything unconditionally).
  shared_flag_args=()
  if grep -q -- '--no-shared-dispatch' "$clone_dir/install.sh" 2>/dev/null; then
    # EFFECTIVE_SHARED_DISPATCH may differ from the manifest's recorded
    # value when codex is in hosts.wire (T.12: AGENTS.md is Codex's primary
    # surface, so --no-shared-dispatch is overridden at execution time).
    if [[ "$EFFECTIVE_SHARED_DISPATCH" == "true" ]]; then
      shared_flag_args=(--shared-dispatch)
    else
      shared_flag_args=(--no-shared-dispatch)
    fi
  else
    warn "$name installer predates --shared-dispatch (legacy). It will compose AGENTS.md/CLAUDE.md regardless of your preference."
    if [[ "$EFFECTIVE_SHARED_DISPATCH" != "true" ]]; then
      warn "  To honor shared_dispatch: false, upgrade $name to the version carrying the flag."
    fi
  fi

  ui_progress_line "$_member_idx" "$_member_total" "$name@$version" "installing"
  _install_ok=true
  run_installer_captured "$name" "${VERBOSITY:-default}" "$clone_dir" \
    --target "$target" \
    --hosts "$HOSTS_CSV" \
    "${shared_flag_args[@]}" \
    ${NON_INTERACTIVE:+--non-interactive} \
    --force \
    || { _install_ok=false; true; }

  if [[ "$_install_ok" == "false" ]]; then
    ui_failed_card "$name" "install.sh returned non-zero"
    _sync_has_failure=true
    continue
  fi

  # ─── Host-leakage prune (PR-I2) ────────────────────────────────────────
  # Run AFTER the installer so we operate on the freshly-emitted tree.
  # Strict check runs first so its violations reflect the installer's
  # actual output (before either prune pass mutates the tree). The
  # manifest pass is the cooperative path; the pattern pass is the
  # defensive fallback.
  if [[ "$STRICT_HOSTS" == "true" ]]; then
    _strict_lines="$(host_prune_strict_check "$target" "$HOSTS_CSV" || true)"
    if [[ -n "$_strict_lines" ]]; then
      warn "--strict-hosts: $name emitted files without host annotation:"
      while IFS= read -r _vline; do
        [[ -z "$_vline" ]] && continue
        warn "  $_vline"
      done <<< "$_strict_lines"
      _STRICT_VIOLATIONS=$((_STRICT_VIOLATIONS + 1))
    fi
  fi
  host_prune_manifest_pass "$target" "$HOSTS_CSV"
  host_prune_path_patterns "$target" "$HOSTS_CSV"

  # ─── claude-code safety net ────────────────────────────────────────────
  # If the host wiring asked for claude-code but the per-Eidolon installer
  # didn't produce .claude/agents/<name>.md, write a minimal dispatch stub so
  # the agent is at least callable. Never overwrite an existing file.
  #
  # Codex has its own analogous file (.codex/agents/<name>.md) but a parallel
  # safety net is intentionally NOT mirrored here (T.6 of openai-codex-host-
  # support spec): the per-Eidolon install.sh owns Codex subagent emission,
  # and adding a nexus-side fallback would mask non-conformant Eidolons.
  # Add it only if observed empirically to be needed.
  if [[ ",$HOSTS_CSV," == *",claude-code,"* ]] && [[ ! -f ".claude/agents/$name.md" ]]; then
    mkdir -p .claude/agents
    display="$(echo "$entry" | jq -r '.display_name // .name')"
    summary="$(echo "$entry" | jq -r '.methodology.summary // ""')"
    cat > ".claude/agents/$name.md" <<STUB
---
name: $name
description: $display — $summary
---

See ./.eidolons/$name/agent.md for the full methodology.
STUB
    info "  wrote .claude/agents/$name.md (nexus safety net)"
  fi

  # ─── codex safety net (.toml) — G10 ──────────────────────────────────
  # Codex reads ONLY .codex/agents/*.toml — the .md files written by per-Eidolon
  # installers are never read (G10). Write a minimal .toml stub when absent.
  # Never overwrite an existing .toml (installer owns it post-creation).
  # [ASSUMPTION A2]: flat key-value TOML without section header is valid for Codex.
  if [[ ",$HOSTS_CSV," == *",codex,"* ]] && [[ ! -f ".codex/agents/$name.toml" ]]; then
    mkdir -p .codex/agents
    display="$(echo "$entry" | jq -r '.display_name // .name')"
    summary="$(echo "$entry" | jq -r '.methodology.summary // ""')"
    printf 'name = "%s"\n' "$name" > ".codex/agents/$name.toml"
    printf 'description = "%s"\n' "$display — $summary" >> ".codex/agents/$name.toml"
    printf 'instructions = "See .eidolons/%s/agent.md for the full methodology."\n' "$name" \
      >> ".codex/agents/$name.toml"
    info "  wrote .codex/agents/$name.toml (nexus safety net, G10)"
  fi

  # ─── copilot safety net (.agent.md) — G3/G8 ─────────────────────────
  # Copilot custom agents require .github/agents/<name>.agent.md (YAML frontmatter).
  # Per-Eidolon installers do not write this today (G8). Write a stub when absent.
  if [[ ",$HOSTS_CSV," == *",copilot,"* ]] && [[ ! -f ".github/agents/$name.agent.md" ]]; then
    mkdir -p .github/agents
    display="$(echo "$entry" | jq -r '.display_name // .name')"
    summary="$(echo "$entry" | jq -r '.methodology.summary // ""')"
    cat > ".github/agents/$name.agent.md" <<AGENTMD
---
name: $name
description: $display — $summary
---

See .eidolons/$name/agent.md for the full methodology.
AGENTMD
    info "  wrote .github/agents/$name.agent.md (nexus safety net, G3/G8)"
  fi

  # Override install.manifest.json's version field with the actual git tag
  # shipped. Per-Eidolon installers hardcode EIDOLON_VERSION and don't bump
  # on patch releases (ships as "1.0.0" even when the tag is v1.0.3),
  # which makes manifests lie about which patch landed on disk. Derived
  # version wins because the git tag is the release truth.
  if [[ -f "$target/install.manifest.json" ]]; then
    actual_tag="$(git -C "$clone_dir" describe --tags --exact-match HEAD 2>/dev/null \
                  || git -C "$clone_dir" describe --tags 2>/dev/null \
                  || echo "")"
    if [[ -n "$actual_tag" ]]; then
      actual_ver="${actual_tag#v}"
      tmp_m="$(mktemp)"
      if jq --arg v "$actual_ver" '.version = $v' "$target/install.manifest.json" > "$tmp_m"; then
        mv "$tmp_m" "$target/install.manifest.json"
        chmod 0644 "$target/install.manifest.json" 2>/dev/null || true
      else
        rm -f "$tmp_m"
      fi
    fi
  fi

  # Pull the manifest emitted by the per-Eidolon install.sh
  if [[ -f "$target/install.manifest.json" ]]; then
    ver="$(jq -r '.version' "$target/install.manifest.json" 2>/dev/null || echo "$version")"
    commit="$(git -C "$clone_dir" rev-parse HEAD)"
    tree="$(git -C "$clone_dir" rev-parse 'HEAD^{tree}' 2>/dev/null || echo "")"
    archive_sha="$(release_metadata_for "$name" "$ver" 2>/dev/null | jq -r '.archive_sha256 // empty' 2>/dev/null || echo "")"
    manifest_sha="$(lock_manifest_sha256 "$target/install.manifest.json" 2>/dev/null || echo "")"
    verification="$(release_integrity_status "$name" "$ver")"
    cat >> "$LOCK_TMP" <<LOCK
  - name: $name
    version: "$ver"
    resolved: "github:$(echo "$entry" | jq -r '.source.repo')@$commit"
    commit: "$commit"
    tree: "$tree"
    archive_sha256: "$archive_sha"
    manifest_sha256: "$manifest_sha"
    verification: "$verification"
    target: "$target"
    hosts_wired: $(jq -c '.hosts_wired' "$target/install.manifest.json")
LOCK
  else
    warn "$name did not produce install.manifest.json (not strictly EIIS-conformant)"
    commit="$(git -C "$clone_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
    tree="$(git -C "$clone_dir" rev-parse 'HEAD^{tree}' 2>/dev/null || echo "")"
    archive_sha="$(release_metadata_for "$name" "$version" 2>/dev/null | jq -r '.archive_sha256 // empty' 2>/dev/null || echo "")"
    verification="$(release_integrity_status "$name" "$version")"
    cat >> "$LOCK_TMP" <<LOCK
  - name: $name
    version: "$version"
    resolved: "github:$(echo "$entry" | jq -r '.source.repo')@$commit"
    commit: "$commit"
    tree: "$tree"
    archive_sha256: "$archive_sha"
    verification: "$verification"
    target: "$target"
    manifest_missing: true
LOCK
  fi

  # ─── ACQUIRED card ────────────────────────────────────────────────────
  # Only shown when this was a fresh install (member or version changed).
  # Repeat runs at the same name@version (idempotent re-run) skip the
  # card; the party roster at end-of-sync confirms the current state.
  if [[ "$_is_fresh_install" == "true" ]]; then
    _acq_ver="${ver:-$version}"
    _acq_meth_cycle="$(echo "$entry" | jq -r '.methodology.cycle // "—"')"
    _acq_handoff="$(echo "$entry" | jq -r '.handoffs.downstream | if . == null or length == 0 then "—" else join(", ") end')"
    _acq_tier="$(echo "$entry" | jq -r '.status // "shipped"')"
    _acq_hosts="$(jq -r '(.hosts_wired // []) | join(",")' "$target/install.manifest.json" 2>/dev/null || echo "$HOSTS_CSV")"
    ui_acquire_card "$name" "$_acq_ver" "$_acq_meth_cycle" "$_acq_handoff" "$_acq_tier" "$target" "$_acq_hosts"
    _member_new_count=$((_member_new_count + 1))
  else
    info "$name@$version already installed — no card emitted"
  fi
done <<< "$MEMBERS_JSON"

# ─── MCP-to-Eidolon tool-surface wiring (spec §10.1, O7) ─────────────────────
# Per-Eidolon installers rewrite .claude/agents/<n>.md from a heredoc on every
# sync — wiping any prior MCP wiring. Re-apply AFTER the per-member loop so
# the wiring always lands on top of the freshly-written agent files.
# Uses eidolons.mcp.lock as the source of truth (not the catalogue) — this
# ensures only installed MCPs are wired, never uninstalled ones.
# Soft failure: individual file errors warn and continue (spec §10.4).
if [ -f "$(mcp_lockfile)" ]; then
  mcp_wiring_reapply_all
fi

# ─── Model frontmatter wiring ────────────────────────────────────────────────
# Apply model: managed blocks to every wired host's agent files AFTER the MCP
# wiring pass (so model: lands last, on top of all other frontmatter patches).
# Sync-time drift policy: warn-and-preserve hand-authored model: lines.
# Skipped when no models block is present in eidolons.yaml (performance fast-path).
if model_resolve_init 2>/dev/null; then
  if model_has_block 2>/dev/null; then
    model_wiring_apply_all 0 2>/dev/null || true
  fi
fi

# ─── Append hosts block to lockfile (R3 Block 1) ─────────────────────────
# Mirrors manifest hosts configuration at sync time for traceability.
# pointer_targets written only when non-empty (preserves backward compat).
{
  echo "hosts:"
  echo "  wire: [$(echo "$HOSTS_CSV" | sed 's/,/, /g')]"
  echo "  shared_dispatch: $EFFECTIVE_SHARED_DISPATCH"
  echo "  strict: $STRICT_HOSTS"
  if [[ -n "$POINTER_TARGETS_CSV" ]]; then
    echo "  pointer_targets: [$(echo "$POINTER_TARGETS_CSV" | sed 's/,/, /g')]"
  fi
} >> "$LOCK_TMP"

# ─── B6: Build _compose_sources (R5-D8) + Append composition block ───────
# _compose_sources is built here (before the lock is finalised) so that the
# composition block in eidolons.lock reflects the ACTUAL sources the compose
# pass will use, not a hardcoded list. The compose_eidolons_md call below
# reuses the same variable — no redundant computation.
#
# Phase 1: seed from POINTER_TARGETS_CSV.
_compose_sources=""
for _cpt in $(echo "$POINTER_TARGETS_CSV" | tr ',' ' '); do
  [[ -z "$_cpt" ]] && continue
  _compose_sources="$_compose_sources ./$_cpt"
done
# Phase 2 (R5-D4): universal marker-guard hoist across the closed vendor set.
# For each vendor file on disk that carries any non-dispatch-pointer Eidolon
# content marker, add it to _compose_sources (deduped). Bash 3.2: hardcoded
# closed-set iteration — must match the set in _validate_pointer_targets_csv
# (lib.sh). Cross-reference: both lists must stay in sync when new vendor
# files are added to the protocol.
for _vfile in CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md; do
  [[ -f "$_vfile" ]] || continue
  grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' "$_vfile" 2>/dev/null || continue
  grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' "$_vfile" 2>/dev/null \
    | grep -vqE 'eidolon:dispatch-pointer' || continue
  case " $_compose_sources " in
    *" ./$_vfile "*) : ;;  # already present — dedupe
    *) _compose_sources="$_compose_sources ./$_vfile" ;;
  esac
done
_compose_sources="$(echo "$_compose_sources" | xargs 2>/dev/null || true)"

# Documents the composition pass's inputs and target for traceability.
# hoisted_from derived from actual _compose_sources (R5-D8).
# Additive only; no top-level schema bump required (schema_version is
# namespaced under composition.*).
_hoisted_list=""
for _src in $_compose_sources; do
  _base="${_src#./}"
  if [[ -z "$_hoisted_list" ]]; then
    _hoisted_list="    - $_base"
  else
    _hoisted_list="$_hoisted_list
    - $_base"
  fi
done
{
  echo "composition:"
  echo "  target: EIDOLONS.md"
  if [[ -n "$_hoisted_list" ]]; then
    echo "  hoisted_from:"
    printf '%s\n' "$_hoisted_list"
  else
    echo "  hoisted_from: []"
  fi
  echo "  agents_md_role: hoisted"
  echo "  schema_version: 1"
} >> "$LOCK_TMP"
unset _hoisted_list _src _base

# ─── LOCK stage ─────────────────────────────────────────────────────────
[[ "${VERBOSITY:-default}" == "verbose" ]] && ui_section "LOCK  eidolons.lock"
mv "$LOCK_TMP" "$PROJECT_LOCK"
chmod 0644 "$PROJECT_LOCK" 2>/dev/null || true
ok "Wrote $PROJECT_LOCK"

# ─── MIRROR stage ────────────────────────────────────────────────────────
[[ "${VERBOSITY:-default}" == "verbose" ]] && ui_section "MIRROR  cortex + deep tables"

# ─── Mirror cortex into consumer project ─────────────────────────────────
# The cortex (EIDOLONS.md + deep tables) is a nexus-level concern, not a
# per-Eidolon one. Per spec §11.1 and invariant [F §9 #10] the mirror lands
# at ./.eidolons/cortex/ (dot-prefixed install convention).
# Deep tables (trance-matrix.md, handoff-graph.md, validation-gates.md,
# README.md) are also mirrored so on-consumer self-references in EIDOLONS.md
# resolve correctly (option (a) per design note in the follow-up spec).
# All copies are idempotent: files are only written when content differs.
CORTEX_SRC="$NEXUS/EIDOLONS.md"
CORTEX_DEST="./.eidolons/cortex/EIDOLONS.md"
CORTEX_DEEP_SRC="$NEXUS/methodology/cortex"
CORTEX_DEEP_DEST="./.eidolons/cortex"
if [[ "$DRY_RUN" == "true" ]]; then
  info "  [dry-run] would mirror cortex to $CORTEX_DEST"
  info "  [dry-run] would mirror deep tables to $CORTEX_DEEP_DEST/"
elif [[ -f "$CORTEX_SRC" ]]; then
  mkdir -p "./.eidolons/cortex"
  if [[ ! -f "$CORTEX_DEST" ]] || ! diff -q "$CORTEX_SRC" "$CORTEX_DEST" >/dev/null 2>&1; then
    cp "$CORTEX_SRC" "$CORTEX_DEST"
    ok "Mirrored cortex → $CORTEX_DEST"
  else
    info "Cortex already up-to-date at $CORTEX_DEST"
  fi
  # Mirror deep companion tables if the source directory exists.
  if [[ -d "$CORTEX_DEEP_SRC" ]]; then
    for _deep_file in trance-matrix.md handoff-graph.md validation-gates.md README.md memory-protocol.md; do
      _src="$CORTEX_DEEP_SRC/$_deep_file"
      _dst="$CORTEX_DEEP_DEST/$_deep_file"
      if [[ -f "$_src" ]]; then
        if [[ ! -f "$_dst" ]] || ! diff -q "$_src" "$_dst" >/dev/null 2>&1; then
          cp "$_src" "$_dst"
          ok "Mirrored cortex deep table → $_dst"
        else
          info "Cortex deep table already up-to-date: $_dst"
        fi
      fi
    done
  fi
else
  warn "Cortex source not found at $CORTEX_SRC — skipping mirror"
fi

# ─── HOST-WIRE stage ─────────────────────────────────────────────────────
[[ "${VERBOSITY:-default}" == "verbose" ]] && ui_section "HOST-WIRE  dispatch pointer"

# ─── Cortex host-doc injection ────────────────────────────────────────────
# When shared-dispatch is active, inject a pointer block into each root
# host-doc surface so the host LLM is directed to the cortex at session
# start. The block is marker-bounded (<!-- eidolon:cortex start/end -->) and
# idempotent. It is NOT injected when shared-dispatch is off: a pointer to
# per-Eidolon dispatch is useless without the per-Eidolon sections to
# dispatch to. Mirrors the per-Eidolon upsert pattern via upsert_marker_block.
CORTEX_BLOCK="## Eidolons Routing Cortex

**Default operating mode:** route all non-trivial work through the Eidolons pipeline — this is the default, not an opt-in. The orchestrator delegates to Eidolon roles via the cortex and does not implement, spec, or scout directly. Answer directly only when a prompt is trivial, conversational, or a single-fact lookup.

**Read:** \`.eidolons/cortex/EIDOLONS.md\` — always-loaded descriptor table + dispatch protocol. It tells you which Eidolon (or chain) handles the prompt, at what tier (\`standard\` is the default; \`TRANCE\` is gated, never default), and what hand-off contract to use.

**Deep tables** (load on demand): \`.eidolons/cortex/trance-matrix.md\`, \`.eidolons/cortex/handoff-graph.md\`, \`.eidolons/cortex/validation-gates.md\`."

if [[ "$DRY_RUN" == "true" ]]; then
  if [[ "$EFFECTIVE_SHARED_DISPATCH" == "true" ]]; then
    info "  [dry-run] would inject cortex block into pointer_targets (shared-dispatch on)"
  else
    info "  [dry-run] skipping cortex host-doc injection (shared-dispatch off)"
  fi
elif [[ "$EFFECTIVE_SHARED_DISPATCH" == "true" ]]; then
  # D12: Cortex injection now iterates POINTER_TARGETS_CSV (not hardcoded set).
  # The existing per-host gate (_cortex_doc_host) remains as an inner filter:
  # pointer_targets is an ADDITIONAL gate on top, not a replacement.
  # AGENTS.md special case: when AGENTS.md ∈ pointer_targets, write cortex
  # if codex OR opencode is wired (EIIS v1.1 §4.1.0). Explicit pointer_targets
  # choice wins over host-wire inference.
  for _host_doc in $(echo "$POINTER_TARGETS_CSV" | tr ',' ' '); do
    [[ -z "$_host_doc" ]] && continue
    _host_for_doc="$(_cortex_doc_host "$_host_doc")"
    if [[ "$_host_doc" == "AGENTS.md" ]]; then
      if [[ ",${HOSTS_CSV}," != *",codex,"* ]] && [[ ",${HOSTS_CSV}," != *",opencode,"* ]]; then
        info "  skipping cortex injection in AGENTS.md (codex/opencode not in hosts.wire)"
        continue
      fi
    elif [[ -n "$_host_for_doc" ]] && [[ ",${HOSTS_CSV}," != *",${_host_for_doc},"* ]]; then
      info "  skipping cortex injection in $_host_doc (host=$_host_for_doc not in hosts.wire)"
      continue
    fi
    upsert_marker_block "$_host_doc" "cortex" "$CORTEX_BLOCK"
  done
  ok "Cortex pointer block injected into pointer_targets docs"
else
  info "Shared dispatch off — skipping cortex host-doc injection"
fi

# ─── Cursor cortex surface: .cursor/rules/eidolons-cortex.mdc (R9 / G4) ──
# Written when cursor ∈ hosts.wire AND shared-dispatch is on.
# Uses the same digest awk as harness_hook.sh (Roster Index + Dispatch Protocol).
# The .mdc file is NOT a pointer_targets vendor file; it is cursor-specific and
# gated directly on cursor ∈ HOSTS_CSV. The closed pointer-target whitelist is
# unchanged.
if [[ "$DRY_RUN" == "true" ]]; then
  if [[ ",${HOSTS_CSV}," == *",cursor,"* ]] && [[ "$EFFECTIVE_SHARED_DISPATCH" == "true" ]]; then
    info "  [dry-run] would write .cursor/rules/eidolons-cortex.mdc (cursor wired)"
  fi
elif [[ ",${HOSTS_CSV}," == *",cursor,"* ]] && [[ "$EFFECTIVE_SHARED_DISPATCH" == "true" ]]; then
  _cortex_src=".eidolons/cortex/EIDOLONS.md"
  if [[ -f "$_cortex_src" ]]; then
    # Extract Roster Index and Dispatch Protocol sections (mirrors harness_hook.sh:53-58).
    _mdc_digest="$(awk '
      /^## Roster Index/ { in_section=1 }
      /^## Dispatch Protocol/ { in_section=1 }
      /^## / && !/^## Roster Index/ && !/^## Dispatch Protocol/ { in_section=0 }
      in_section { print }
    ' "$_cortex_src" 2>/dev/null | head -c 4000 || true)"

    if [[ -z "$_mdc_digest" ]]; then
      _mdc_digest="$(head -c 4000 "$_cortex_src" 2>/dev/null || true)"
    fi

    _mdc_body="${_mdc_digest}

> Deep tables: \`.eidolons/cortex/trance-matrix.md\`, \`.eidolons/cortex/handoff-graph.md\`, \`.eidolons/cortex/validation-gates.md\`"

    mkdir -p ".cursor/rules"
    _mdc_file=".cursor/rules/eidolons-cortex.mdc"
    _mdc_frontmatter="---
description: Eidolons routing cortex — read before any non-trivial prompt.
alwaysApply: true
---"

    if [[ ! -f "$_mdc_file" ]]; then
      # Write fresh: frontmatter + markers + body.
      printf '%s\n' "$_mdc_frontmatter" > "$_mdc_file"
      printf '\n' >> "$_mdc_file"
      upsert_marker_block "$_mdc_file" "cortex" "$_mdc_body"
      ok "Wrote .cursor/rules/eidolons-cortex.mdc"
    else
      # File exists: upsert_marker_block rewrites only the marker interior.
      # Check idempotency: compare before/after.
      _mdc_before="$(cat "$_mdc_file" 2>/dev/null || echo "")"
      upsert_marker_block "$_mdc_file" "cortex" "$_mdc_body"
      _mdc_after="$(cat "$_mdc_file" 2>/dev/null || echo "")"
      if [[ "$_mdc_before" == "$_mdc_after" ]]; then
        info ".cursor/rules/eidolons-cortex.mdc unchanged (no-op)"
      else
        ok "Updated .cursor/rules/eidolons-cortex.mdc"
      fi
    fi
  else
    info "  cursor wired but .eidolons/cortex/EIDOLONS.md absent — skipping .mdc write (run sync again after cortex is installed)"
  fi
fi

# ─── EIDOLONS.md composition pass (B1 / R3 Block 2 + Block 8) ───────────
# Hoist per-eidolon marker blocks from pointer_targets sources into EIDOLONS.md.
# Sources are derived from POINTER_TARGETS_CSV (v1.7.0+). Legacy <name>-pointer
# stubs are removed during this pass (idempotent migration D1).
# Must run BEFORE apply_dispatch_pointers so dispatch-pointer lands on already-
# reduced source files.
# Skipped on --dry-run; compose_eidolons_md is idempotent so re-runs are safe.
if [[ "$DRY_RUN" == "true" ]]; then
  info "  [dry-run] would run compose_eidolons_md pass (sources from pointer_targets: ${POINTER_TARGETS_CSV:-(none)})"
else
  # _compose_sources was built above (before the lock block) so lock's
  # composition.hoisted_from reflects the same sources used here.
  _members_space="$(echo "$MEMBERS_JSON" | jq -r '.name' | tr '\n' ' ')"
  if [[ -z "$_compose_sources" ]]; then
    info "  compose_eidolons_md: no pointer_targets configured and no vendor markers detected — skipping composition pass"
  else
    compose_eidolons_md "$_members_space" "$_compose_sources"
    ok "EIDOLONS.md composition pass complete"
  fi
fi
unset _compose_sources _members_space _cpt _vfile

# ─── Dispatch-pointer injection (R3 Block 4) ─────────────────────────────
# Writes the dispatch-pointer block to every vendor file in POINTER_TARGETS_CSV.
# AGENTS.md is now a first-class target when pointer_targets includes it (D6).
# Warn-and-append fires once per vendor on first insertion into populated content.
if [[ "$DRY_RUN" == "true" ]]; then
  info "  [dry-run] would inject dispatch-pointer block into pointer_targets: ${POINTER_TARGETS_CSV:-(none)}"
else
  apply_dispatch_pointers "$POINTER_TARGETS_CSV" "$HOSTS_CSV"
  ok "Dispatch-pointer block injected into vendor docs"
fi

# ─── Harness marker (F7-3 / S20b) ───────────────────────────────────────
# If Junction is installed ($EIDOLONS_HOME/cache/junction@*/), write a
# manifest.json marker at ./.eidolons/harness/manifest.json so consumer
# projects have a uniform discovery surface for harness + Eidolons.
#
# Idempotency: the marker is written only when content would differ, so
# repeated sync runs on an unchanged install produce no file mutations.
# The installed_at timestamp is intentionally OMITTED to keep the file
# byte-stable across re-runs (stable content = no VCS noise).
# If Junction is absent, the marker dir is removed (clean removal).
_harness_cache_dir=""
_harness_ver=""
for _hdir in "${CACHE_DIR}/junction@"*/; do
  if [[ -d "$_hdir" ]]; then
    _harness_cache_dir="${_hdir%/}"
    _harness_ver="${_harness_cache_dir##*/junction@}"
    break
  fi
done

HARNESS_MARKER="./.eidolons/harness/manifest.json"

if [[ -n "$_harness_cache_dir" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    info "  [dry-run] would write harness marker $HARNESS_MARKER (junction@${_harness_ver})"
  else
    _harness_json="{\"name\": \"junction\", \"version\": \"${_harness_ver}\", \"cache_path\": \"${_harness_cache_dir}\"}"
    _write_marker=true
    if [[ -f "$HARNESS_MARKER" ]]; then
      _existing="$(cat "$HARNESS_MARKER" 2>/dev/null || true)"
      if [[ "$_existing" == "$_harness_json" ]]; then
        _write_marker=false
      fi
    fi
    if [[ "$_write_marker" == "true" ]]; then
      mkdir -p "./.eidolons/harness"
      printf '%s\n' "$_harness_json" > "$HARNESS_MARKER"
      ok "Wrote harness marker → $HARNESS_MARKER"
    else
      info "Harness marker already up-to-date at $HARNESS_MARKER"
    fi
  fi
else
  # Junction absent — remove marker if present (idempotent).
  if [[ -d "./.eidolons/harness" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "  [dry-run] would remove harness marker dir (Junction not installed)"
    else
      rm -rf "./.eidolons/harness"
      info "Removed harness marker (Junction not installed)"
    fi
  fi
fi

# ─── Harness shim refresh ────────────────────────────────────────────────
# If harness is installed (harness.schema_version present in lock), refresh
# shim contents from the current template. Does NOT install if absent (opt-in).
_harness_installed="$(jq -r '.harness.schema_version // "absent"' "$PROJECT_LOCK" 2>/dev/null || echo "absent")"
if [[ "$_harness_installed" != "absent" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    info "  [dry-run] would refresh harness shims (harness installed, schema_version=$_harness_installed)"
  else
    bash "$SELF_DIR/harness_install.sh" --refresh-shims-only || true
  fi
fi
unset _harness_installed

# ─── MCP lockfile drift (warn-only; never installs per NG3) ─────────────
# Surfaces any MCP entries in eidolons.mcp.lock so the operator knows they
# are present, but does NOT install, upgrade, or touch them.  MCP install
# is always explicit via 'eidolons mcp install / sync / upgrade'.
_mcp_lf="./eidolons.mcp.lock"
if [[ -f "$_mcp_lf" ]] && command -v jq >/dev/null 2>&1; then
  # Source lib_mcp to get yaml_to_json-based reader.
  # shellcheck disable=SC1091
  . "$SELF_DIR/lib_mcp.sh"
  _mcp_lf_json="$(mcp_lock_read 2>/dev/null || echo '{}')"
  _mcp_installed="$(printf '%s' "$_mcp_lf_json" \
    | jq -r '(.mcps // [])[] | "\(.name)@\(.version)"' 2>/dev/null || true)"
  if [[ -n "$_mcp_installed" ]]; then
    echo ""
    info "MCP wiring (from eidolons.mcp.lock — not modified by sync):"
    while IFS= read -r _mcp_entry; do
      [[ -n "$_mcp_entry" ]] || continue
      info "  · $_mcp_entry"
    done <<< "$_mcp_installed"
    info "  Run 'eidolons mcp upgrade --all' to upgrade, or 'eidolons mcp health' to probe."
  fi
fi

# ─── Strict-hosts gate (PR-I2) ───────────────────────────────────────────
# If any per-member strict check raised violations, fail the run. Errors
# were already emitted inline as `warn` lines; this is the abort. Runs
# before the party roster so a failed sync doesn't celebrate prematurely.
if [[ "$_STRICT_VIOLATIONS" -gt 0 ]]; then
  warn "--strict-hosts: $_STRICT_VIOLATIONS Eidolon(s) wrote files without manifest host annotations (details above)."
  warn "Run without --strict-hosts to prune by path patterns instead, or upgrade the offending Eidolon(s) to a release with annotated install.manifest.json (EIIS soft dep FU-I2.1)."
  exit 1
fi

# ─── Party roster card ───────────────────────────────────────────────────
# Always emitted under default and verbose. Under quiet, emit only when
# there were new installs (so a no-op quiet run stays truly quiet except
# for the roster, which still prints to confirm current state).
if [[ "${VERBOSITY:-default}" != "quiet" ]] || [[ "$_member_new_count" -gt 0 ]]; then
  ui_party_roster "$PROJECT_LOCK"
fi

# ─── Final guidance ──────────────────────────────────────────────────────
echo "" >&2
ok "Sync complete."
echo "" >&2
if [[ "${VERBOSITY:-default}" != "quiet" ]]; then
  cat >&2 <<EOF
Next steps:
  ${BOLD}eidolons doctor${RESET}              verify host wiring
  ${BOLD}eidolons list${RESET}                show installed members
  ${BOLD}cat $PROJECT_LOCK${RESET}            review resolved versions

Commit both eidolons.yaml and eidolons.lock to VCS.
EOF
fi

# Exit non-zero when any member install failed.
if [[ "$_sync_has_failure" == "true" ]]; then
  exit 1
fi
