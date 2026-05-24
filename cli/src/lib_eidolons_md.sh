#!/usr/bin/env bash
# cli/src/lib_eidolons_md.sh — EIDOLONS.md composition helpers
# ═══════════════════════════════════════════════════════════════════════════
# Provides compose_eidolons_md: hoists per-eidolon marker blocks from
# ./CLAUDE.md into ./EIDOLONS.md and replaces source blocks with thin pointer
# blocks. Idempotent, bash 3.2 safe, all log output to stderr.
#
# Designed to be sourced by sync.sh AFTER lib.sh (depends on
# upsert_marker_block, remove_marker_block, and info from lib.sh).
# shellcheck shell=bash

_EIDOLONS_MD_PATH="${_EIDOLONS_MD_PATH:-./EIDOLONS.md}"
_EIDOLONS_MD_SOURCE="${_EIDOLONS_MD_SOURCE:-./CLAUDE.md}"

# _eidolons_md_preamble
#
# Writes the canonical EIDOLONS.md preamble to stdout. Called once on file
# creation. Bash 3.2 safe (printf line-by-line, no heredoc in $()).
_eidolons_md_preamble() {
  printf '%s\n' \
    '# EIDOLONS — canonical agent dispatch & methodology surface' \
    '' \
    'This file is managed by `eidolons sync`. It composes the per-Eidolon' \
    'methodology references hoisted from host-vendor files. Do not edit' \
    'inside `<!-- eidolon:<name> start --> ... end -->` markers; manual edits' \
    'above the first marker block or below the last are preserved.' \
    '' \
    'Vendor pointer files (`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`)' \
    'redirect host LLMs here. `AGENTS.md` remains the Codex primary surface' \
    'per EIIS v1.1 §4.1.0 with a supplementary pointer to this file.'
}

# compose_eidolons_md <member_names_space_separated>
#
# For each member name in the space-separated list:
#   1. Check ./CLAUDE.md for a `<!-- eidolon:<name> start/end -->` block.
#      (NOT <!-- eidolon:<name>-pointer -->: that means already hoisted.)
#   2. Extract the block body (between start/end markers) into a temp file.
#   3. Upsert the body into ./EIDOLONS.md under the same marker name.
#   4. Remove the original block from ./CLAUDE.md via remove_marker_block.
#   5. Insert a thin pointer block under `<name>-pointer` marker name
#      (distinct from `<name>`, making subsequent calls skip this member).
#
# Idempotency: a `<name>-pointer` start marker in CLAUDE.md means content
# was already hoisted; the pass skips it. A `<name>` start marker means
# content is still there and must be hoisted.
#
# AGENTS.md is NOT scanned (per FINDING-005 / EIIS v1.1 §4.1.0).
# Preamble written once on EIDOLONS.md creation (not rewritten on re-runs).
# All log output to stderr. Bash 3.2 safe.
compose_eidolons_md() {
  local members="$1"
  local src="$_EIDOLONS_MD_SOURCE"
  local dst="$_EIDOLONS_MD_PATH"

  # Nothing to hoist if source is absent.
  if [[ ! -f "$src" ]]; then
    info "  compose_eidolons_md: $src not found — skipping composition pass"
    return 0
  fi

  # Nothing to do with an empty member list.
  if [[ -z "$members" ]]; then
    info "  compose_eidolons_md: empty member list — skipping composition pass"
    return 0
  fi

  # Create dst with preamble iff absent.
  if [[ ! -f "$dst" ]]; then
    _eidolons_md_preamble > "$dst"
    info "  compose_eidolons_md: created $dst with preamble"
  fi

  local name body_tmp ptr_text
  for name in $members; do
    local start="<!-- eidolon:${name} start -->"
    local pointer_start="<!-- eidolon:${name}-pointer start -->"

    # Skip if the block is absent from source (nothing to hoist).
    if ! grep -qF "$start" "$src" 2>/dev/null; then
      info "  compose_eidolons_md: no $name block in $src — skipping"
      continue
    fi

    # Skip if a pointer block already exists (already hoisted in a prior run).
    if grep -qF "$pointer_start" "$src" 2>/dev/null; then
      info "  compose_eidolons_md: $name already hoisted (pointer block present) — skipping"
      continue
    fi

    # Extract body (lines between start and end markers, exclusive).
    local end="<!-- eidolon:${name} end -->"
    body_tmp="$(mktemp)"
    awk -v s="$start" -v e="$end" '
      $0 == s { inblk = 1; next }
      $0 == e { inblk = 0; next }
      inblk   { print }
    ' "$src" > "$body_tmp"

    # Hoist body into EIDOLONS.md under the same marker name.
    upsert_marker_block "$dst" "$name" "$(cat "$body_tmp")"
    rm -f "$body_tmp"

    # Remove the original content block from CLAUDE.md.
    remove_marker_block "$src" "$name"

    # Insert a thin pointer block under <name>-pointer marker.
    ptr_text="See [\`./EIDOLONS.md\`](./EIDOLONS.md) §${name} — managed by \`eidolons sync\`. Do not edit between markers."
    upsert_marker_block "$src" "${name}-pointer" "$ptr_text"

    info "  compose_eidolons_md: hoisted $name → $dst; replaced source with pointer"
  done

  return 0
}
