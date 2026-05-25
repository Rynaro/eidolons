#!/usr/bin/env bash
# cli/src/lib_eidolons_md.sh — EIDOLONS.md composition helpers
# ═══════════════════════════════════════════════════════════════════════════
# Provides compose_eidolons_md: hoists per-eidolon marker blocks from source
# files (CLAUDE.md and AGENTS.md by default) into EIDOLONS.md. In v1.7.0+,
# <name>-pointer stubs are NO LONGER written back — dispatch-pointer is the
# sole EIDOLONS.md reference. Legacy stubs are removed during the compose
# pass (idempotent). Idempotent, bash 3.2 safe, all log output to stderr.
#
# Designed to be sourced by sync.sh AFTER lib.sh (depends on
# upsert_marker_block, remove_marker_block, collapse_consecutive_blanks,
# and info from lib.sh).
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
# Hoists per-eidolon marker blocks from each source file into EIDOLONS.md.
# In v1.7.0+, NO <name>-pointer stub is written back; legacy stubs from
# v1.6.0 installs are removed during this pass (idempotent).
# Idempotent. Bash 3.2 safe.
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
#       4. Removes any legacy <member>-pointer block from source (migration).
#       5. Strips trailing blank lines from source (existing post-remove cleanup).
#       6. Runs collapse_consecutive_blanks on source (v1.6.0 leading-blank cleanup).
#
# Idempotency:
#   - A <member>-pointer marker in source means block already hoisted in v1.6.0;
#     content block absent → skip hoist; pointer still removed (migration).
#   - A <member> marker means "content to hoist."
#   - Both detection paths exist independently per source.
compose_eidolons_md() {
  local members="$1"
  local sources="${2:-./CLAUDE.md ./AGENTS.md}"
  local dst="$_EIDOLONS_MD_PATH"

  # Nothing to do with an empty member list.
  if [[ -z "$members" ]]; then
    info "  compose_eidolons_md: empty member list — skipping composition pass"
    return 0
  fi

  local src name body_tmp _dst_created=false
  for src in $sources; do
    if [[ ! -f "$src" ]]; then
      info "  compose_eidolons_md: $src not found — skipping"
      continue
    fi

    for name in $members; do
      local start="<!-- eidolon:${name} start -->"

      # v1.7.0 migration: always remove any legacy <name>-pointer block,
      # whether or not there is content to hoist (D1). Idempotent — no-op
      # on greenfield and v1.7.0 installs; cleans v1.6.0 stubs.
      remove_marker_block "$src" "${name}-pointer"

      # Skip content hoist if the content block is absent from this source.
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
      }' "$src" > "$_clean_tmp" && mv "$_clean_tmp" "$src" && chmod 0644 "$src" 2>/dev/null || true

      info "  compose_eidolons_md: hoisted $name from $src → $dst"
    done

    # Collapse any runs of consecutive blank lines left by the removal passes.
    # Cleans up v1.6.0 leading-blank pollution on first v1.7.0 sync. Idempotent.
    collapse_consecutive_blanks "$src"
  done

  return 0
}
