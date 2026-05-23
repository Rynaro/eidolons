#!/usr/bin/env bash
# eidolons sync — install/update Eidolons to match eidolons.yaml
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/ui/prompt.sh"

NON_INTERACTIVE=false
DRY_RUN=false
SKIP_PREVIEW=false

usage() {
  cat <<EOF
eidolons sync — install/update Eidolons to match eidolons.yaml

Usage: eidolons sync [OPTIONS]

Options:
  --non-interactive   Fail on prompts (also skips the pre-install preview)
  --dry-run           Show what would be done without touching disk
  --yes, -y           Skip the pre-install preview confirmation (auto-approve)
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
    -h|--help)         usage; exit 0 ;;
    *)                 echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

manifest_exists || die "No eidolons.yaml found. Run 'eidolons init' first."

MANIFEST_JSON="$(yaml_to_json "$PROJECT_MANIFEST")"
HOSTS_CSV="$(echo "$MANIFEST_JSON" | jq -r '.hosts.wire | join(",")')"
# Default shared_dispatch to false when the key is absent (pre-v1.2 manifests).
SHARED_DISPATCH="$(echo "$MANIFEST_JSON" | jq -r '.hosts.shared_dispatch // false')"
MEMBERS_JSON="$(echo "$MANIFEST_JSON" | jq -c '.members[]')"

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
LOCK_TMP="$(mktemp)"
cat > "$LOCK_TMP" <<EOF
# eidolons.lock — auto-generated by 'eidolons sync'. Commit to VCS.
generated_at: "$(date -u +%FT%TZ)"
eidolons_cli_version: "${EIDOLONS_VERSION:-1.0.0}"
nexus_commit: "$(git -C "$NEXUS" rev-parse HEAD 2>/dev/null || echo unknown)"
members:
EOF

# ─── Per-member install ──────────────────────────────────────────────────
while read -r member; do
  name="$(echo "$member" | jq -r '.name')"
  version_spec="$(echo "$member" | jq -r '.version')"
  # Strip constraint prefix (^, ~, =) for cache key — proper resolution is a future task.
  version="${version_spec#^}"
  version="${version#~}"
  version="${version#=}"

  entry="$(roster_get "$name")"
  target="./.eidolons/$name"

  say "Installing $name@$version → $target"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "  [dry-run] would fetch and install $name"
    continue
  fi

  clone_dir="$(fetch_eidolon "$name" "$version")"

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

  # Delegate to the Eidolon's own install.sh (EIIS §3 contract).
  if [[ ! -x "$clone_dir/install.sh" ]]; then
    warn "$name has no executable install.sh — EIIS v1.0 contract violated. Skipping."
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

  (
    cd "$(pwd)"  # ensure we stay in the consumer project
    bash "$clone_dir/install.sh" \
      --target "$target" \
      --hosts "$HOSTS_CSV" \
      "${shared_flag_args[@]}" \
      ${NON_INTERACTIVE:+--non-interactive} \
      --force
  ) || { warn "$name install failed — continuing"; continue; }

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

  ok "$name installed"
done <<< "$MEMBERS_JSON"

# ─── Write the lock ──────────────────────────────────────────────────────
mv "$LOCK_TMP" "$PROJECT_LOCK"
ok "Wrote $PROJECT_LOCK"

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
    for _deep_file in trance-matrix.md handoff-graph.md validation-gates.md README.md; do
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

# ─── Cortex host-doc injection ────────────────────────────────────────────
# When shared-dispatch is active, inject a pointer block into each root
# host-doc surface so the host LLM is directed to the cortex at session
# start. The block is marker-bounded (<!-- eidolon:cortex start/end -->) and
# idempotent. It is NOT injected when shared-dispatch is off: a pointer to
# per-Eidolon dispatch is useless without the per-Eidolon sections to
# dispatch to. Mirrors the per-Eidolon upsert pattern via upsert_marker_block.
CORTEX_BLOCK="## Eidolons Routing Cortex

When a free-form prompt arrives that doesn't already name an Eidolon, route it via the cortex.

**Read:** \`.eidolons/cortex/EIDOLONS.md\` — always-loaded descriptor table + dispatch protocol. It tells you which Eidolon (or chain) handles the prompt, at what tier (\`standard\` or \`TRANCE\`), and what hand-off contract to use.

**Deep tables** (load on demand): \`.eidolons/cortex/trance-matrix.md\`, \`.eidolons/cortex/handoff-graph.md\`, \`.eidolons/cortex/validation-gates.md\`."

if [[ "$DRY_RUN" == "true" ]]; then
  if [[ "$EFFECTIVE_SHARED_DISPATCH" == "true" ]]; then
    info "  [dry-run] would inject cortex block into root host docs (shared-dispatch on)"
  else
    info "  [dry-run] skipping cortex host-doc injection (shared-dispatch off)"
  fi
elif [[ "$EFFECTIVE_SHARED_DISPATCH" == "true" ]]; then
  for _host_doc in "AGENTS.md" "CLAUDE.md" ".github/copilot-instructions.md"; do
    upsert_marker_block "$_host_doc" "cortex" "$CORTEX_BLOCK"
  done
  ok "Cortex pointer block injected into root host docs"
else
  info "Shared dispatch off — skipping cortex host-doc injection"
fi

# ─── Dispatch-pointer injection (PR-A1) ──────────────────────────────────
# Make vendor-specific files (CLAUDE.md, GEMINI.md,
# .github/copilot-instructions.md) thin pointers to AGENTS.md — the
# source of truth. Independent of shared-dispatch: the dispatch-pointer
# block is always injected so hosts can find their way to AGENTS.md
# even on per-vendor-only setups.
#
# AGENTS.md is deliberately absent from DISPATCH_POINTER_VENDORS — it is
# the target of pointers, never itself a pointer.
#
# Warn-and-append protocol fires once per vendor on first insertion into
# populated content. EIDOLONS_NO_GEMINI=1 opts out of GEMINI.md.
if [[ "$DRY_RUN" == "true" ]]; then
  info "  [dry-run] would inject dispatch-pointer block into $DISPATCH_POINTER_VENDORS"
else
  apply_dispatch_pointers
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

# ─── Final guidance ──────────────────────────────────────────────────────
echo ""
ok "Sync complete."
echo ""
cat <<EOF
Next steps:
  ${BOLD}eidolons doctor${RESET}              verify host wiring
  ${BOLD}eidolons list${RESET}                show installed members
  ${BOLD}cat $PROJECT_LOCK${RESET}            review resolved versions

Commit both eidolons.yaml and eidolons.lock to VCS.
EOF
