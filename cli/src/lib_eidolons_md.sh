#!/usr/bin/env bash
# cli/src/lib_eidolons_md.sh — EIDOLONS.md composition helpers
# ═══════════════════════════════════════════════════════════════════════════
# Provides compose_eidolons_md: hoists per-eidolon marker blocks from source
# files (CLAUDE.md and AGENTS.md by default) into EIDOLONS.md and replaces
# source blocks with thin pointer blocks. Idempotent, bash 3.2 safe, all
# log output to stderr.
#
# Designed to be sourced by sync.sh AFTER lib.sh (depends on
# upsert_marker_block, remove_marker_block, and info from lib.sh).
# shellcheck shell=bash

_EIDOLONS_MD_PATH="${_EIDOLONS_MD_PATH:-./EIDOLONS.md}"

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
    'Vendor pointer files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`,' \
    '`.github/copilot-instructions.md`) redirect host LLMs here via' \
    '`<!-- eidolon:<name>-pointer -->` blocks. `EIDOLONS.md` is the single' \
    'canonical composition surface per `eidolons sync`.'
}

# compose_eidolons_md <members_space_separated> [sources_space_separated]
#
# Hoists per-eidolon marker blocks from each source file into EIDOLONS.md and
# replaces the source blocks with thin pointer blocks. Idempotent. Bash 3.2 safe.
#
# Args:
#   members  — space-separated member names from the roster (required).
#   sources  — space-separated source paths. Default: "./CLAUDE.md ./AGENTS.md".
#              Sources that do not exist are silently skipped (info line on stderr).
#
# Side effects:
#   - Creates EIDOLONS.md with preamble iff absent.
#   - For each (source, member) pair where source has <!-- eidolon:<member> start -->:
#       1. Extracts body via awk (exact-match marker lines).
#       2. Upserts body into EIDOLONS.md under <member> marker.
#       3. Removes original block from source via remove_marker_block.
#       4. Strips trailing blank lines from source (existing post-remove cleanup).
#       5. Inserts <!-- eidolon:<member>-pointer --> block in source.
#
# Idempotency:
#   - A <member>-pointer marker in source means "already hoisted; skip on this pass."
#   - A <member> marker means "content to hoist."
#   - Both detection paths exist independently per source; AGENTS.md can be at
#     state X while CLAUDE.md is at state Y without interference.
compose_eidolons_md() {
  local members="$1"
  local sources="${2:-./CLAUDE.md ./AGENTS.md}"
  local dst="$_EIDOLONS_MD_PATH"

  # Nothing to do with an empty member list.
  if [[ -z "$members" ]]; then
    info "  compose_eidolons_md: empty member list — skipping composition pass"
    return 0
  fi

  local src name body_tmp ptr_text _dst_created=false
  for src in $sources; do
    if [[ ! -f "$src" ]]; then
      info "  compose_eidolons_md: $src not found — skipping"
      continue
    fi

    for name in $members; do
      local start="<!-- eidolon:${name} start -->"

      # Skip if the content block is absent from this source (nothing to hoist).
      # Note: the pointer block alone (<name>-pointer) does NOT prevent hoist —
      # the installer may have re-appended the content block on a subsequent
      # sync (e.g., after the pointer was written on a first pass). The
      # idempotency key is the PRESENCE of the content block, not the pointer.
      if ! grep -qF "$start" "$src" 2>/dev/null; then
        info "  compose_eidolons_md: no $name block in $src — skipping"
        continue
      fi

      # Create dst with preamble iff absent. Written at most once (first hoist).
      if [[ ! -f "$dst" ]]; then
        _eidolons_md_preamble > "$dst"
        info "  compose_eidolons_md: created $dst with preamble"
        _dst_created=true
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
      # Last-write-wins: if both CLAUDE.md and AGENTS.md carry the same member
      # block, the second source's body overwrites the first in EIDOLONS.md.
      upsert_marker_block "$dst" "$name" "$(cat "$body_tmp")"
      rm -f "$body_tmp"

      # Remove the original content block from the source file.
      remove_marker_block "$src" "$name"

      # upsert_marker_block's append mode prepends a blank line ('\n') before
      # the start marker. After remove_marker_block strips the marker+content,
      # this blank line remains as a trailing empty line. Strip ALL trailing
      # blank lines from the source so idempotency holds on re-runs.
      # Bash 3.2 safe: awk stores all lines, trims trailing empties.
      local _clean_tmp
      _clean_tmp="$(mktemp)"
      awk '{
        lines[NR] = $0
      }
      END {
        last = NR
        while (last > 0 && lines[last] == "") last--
        for (i = 1; i <= last; i++) print lines[i]
      }' "$src" > "$_clean_tmp" && mv "$_clean_tmp" "$src"

      # Insert a thin pointer block under <name>-pointer marker name.
      # Same wording for all sources (host-agnostic; the file role is implicit).
      ptr_text="See [\`./EIDOLONS.md\`](./EIDOLONS.md) §${name} — managed by \`eidolons sync\`. Do not edit between markers."
      upsert_marker_block "$src" "${name}-pointer" "$ptr_text"

      info "  compose_eidolons_md: hoisted $name from $src → $dst; replaced source with pointer"
    done
  done

  return 0
}
