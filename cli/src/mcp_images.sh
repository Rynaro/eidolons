#!/usr/bin/env bash
# cli/src/mcp_images.sh — image-focused inventory for 'eidolons mcp images'.
#
# Usage: eidolons mcp images [--json]
#
# Shows a table over oci-image MCPs: NAME / IMAGE / PRESENT / LOCAL / PINNED /
# WIRED / DRIFT / SIZE. Binary (junction) and other kinds are omitted entirely.
# Always exits 0 (docker absence is a cell-level condition, not a failure).
#
# R10 / F3 (ESL change mcp-verify-lock-vs-artifact): DRIFT was a TAUTOLOGY —
# it built `${image}@${pinned}`, inspected THAT exact ref, and compared the
# result back to `pinned`. LOCAL *is* PINNED by construction; `drift="yes"`
# was unreachable (confirmed live: wired to an older digest, this column
# still printed "no"). DRIFT is now wired-vs-locked (WIRED column, computed
# from .mcp.json — no docker required) vs `lock.integrity.value`, the SAME
# question 'eidolons mcp verify' answers as V-OCI-WIRED-MISMATCH. This is a
# genuinely different axis from the old LOCAL-vs-PINNED comparison, which
# stays (LOCAL/PINNED/PRESENT are still docker-derived and unchanged).
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

JSON=false
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=true; shift ;;
    -h|--help)
      cat >&2 <<EOF
eidolons mcp images — image inventory for oci-image MCPs

Usage: eidolons mcp images [--json]

Options:
  --json      Emit a JSON array (one object per oci-image MCP).
  -h, --help  Show this help.

Table columns:
  NAME     catalogue name
  IMAGE    source.image (registry ref, no digest)
  PRESENT  yes | no | (n/a)   — n/a when docker CLI/daemon unavailable
  LOCAL    first 19 chars of the locally-resolved digest, or "—"
  PINNED   first 19 chars of catalogue pins.stable digest
  WIRED    first 19 chars of the digest baked into .mcp.json, or "—"
  DRIFT    no | yes | unknown   (wired vs locked — see below)
  SIZE     human-readable image size, or "—" when absent/unknown

DRIFT is wired-vs-locked (WIRED column vs eidolons.mcp.lock's
integrity.value) — the exact axis 'eidolons mcp verify' names
V-OCI-WIRED-MISMATCH. It needs NO docker: "unknown" when the MCP is not
locked or not wired; "no" when WIRED == locked digest; "yes" otherwise. This
is a DIFFERENT question from LOCAL/PINNED (docker-inspected image vs the
catalogue's pinned digest) — both stay, on separate axes.

Scope: oci-image MCPs ONLY. Binary (junction) and script kinds are omitted.
Exit code: always 0.
EOF
      exit 0
      ;;
    *)
      printf '%s\n' "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

cat_file="$(mcp_catalogue_file)"
if [ ! -f "$cat_file" ]; then
  warn "MCP catalogue not found at: $cat_file"
  exit 0
fi

# Check docker availability once.
_docker_cli_ok=false
_docker_daemon_ok=false
if atlas_aci_check_docker_cli 2>/dev/null; then
  _docker_cli_ok=true
  if atlas_aci_check_docker_daemon 2>/dev/null; then
    _docker_daemon_ok=true
  fi
fi

lock_json="$(mcp_lock_read)"

# _images_get_row NAME IMAGE PINNED_DIGEST LOCKED_DIGEST
# Computes and outputs a JSON row for the --json mode.
#
# R10 / F3: `drift` is wired-vs-locked (WIRED digest, read from .mcp.json —
# no docker needed — vs `locked_digest`, i.e. lock.integrity.value). This is
# the SAME question 'eidolons mcp verify' asks as V-OCI-WIRED-MISMATCH
# (drift_axis: "wired_vs_locked"). LOCAL/PINNED (docker-inspected image vs
# catalogue pin) are a separate, still-present axis — present/local_digest
# are unchanged and remain docker-gated.
_images_get_row_json() {
  local _nm="$1"
  local _img="$2"
  local _pin="$3"
  local _lkd="$4"

  local _present=false
  local _local_digest=""
  local _size_bytes="null"
  local _docker_available=false

  if [ "$_docker_cli_ok" = "true" ] && [ "$_docker_daemon_ok" = "true" ]; then
    _docker_available=true
    if [ -n "$_pin" ]; then
      local _full_ref="${_img}@${_pin}"
      if atlas_aci_check_image "$_full_ref" 2>/dev/null; then
        _present=true
        local _repo_digest
        _repo_digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "$_full_ref" 2>/dev/null || true)"
        if [ -n "$_repo_digest" ]; then
          _local_digest="${_repo_digest##*@}"
        fi
        local _size_raw
        _size_raw="$(docker image inspect --format '{{.Size}}' "$_full_ref" 2>/dev/null || true)"
        if [ -n "$_size_raw" ]; then
          _size_bytes="$_size_raw"
        fi
      fi
    fi
  fi

  # Wired digest — the digest actually baked into .mcp.json for this MCP
  # (cwd-relative; no docker involved). Compute drift wired-vs-locked.
  local _wired_digest _drift
  _wired_digest="$(_mcp_oci_mcpjson_digest "$_nm" "$(pwd)" 2>/dev/null || true)"
  _drift="unknown"
  if [ -n "$_wired_digest" ] && [ -n "$_lkd" ]; then
    if [ "$_wired_digest" = "$_lkd" ]; then
      _drift="no"
    else
      _drift="yes"
    fi
  fi

  jq -n \
    --arg nm "$_nm" \
    --arg img "$_img" \
    --argjson pres "$_present" \
    --arg ld "$_local_digest" \
    --arg pd "$_pin" \
    --arg lkd "$_lkd" \
    --arg wd "$_wired_digest" \
    --arg dr "$_drift" \
    --argjson sz "$_size_bytes" \
    --argjson da "$_docker_available" \
    '{
      name: $nm,
      image: $img,
      kind: "oci-image",
      present: $pres,
      local_digest: (if $ld == "" then null else $ld end),
      pinned_digest: (if $pd == "" then null else $pd end),
      locked_digest: (if $lkd == "" then null else $lkd end),
      wired_digest: (if $wd == "" then null else $wd end),
      drift: $dr,
      drift_axis: "wired_vs_locked",
      size_bytes: $sz,
      docker_available: $da
    }'
}

if [ "$JSON" = "true" ]; then
  _out_arr="[]"

  while IFS= read -r _mname; do
    [ -z "$_mname" ] && continue

    _kind="$(mcp_catalogue_get_field "$_mname" '.kind')"
    [ "$_kind" != "oci-image" ] && continue

    _image="$(mcp_catalogue_get_field "$_mname" '.source.image')"
    _pinned="$(mcp_catalogue_get "$_mname" \
      | jq -r '.versions.releases[.versions.pins.stable].digest // empty')"
    _locked="$(printf '%s' "$lock_json" \
      | jq -r --arg n "$_mname" '(.mcps // [])[] | select(.name == $n) | .integrity.value // ""')"

    _row="$(_images_get_row_json "$_mname" "$_image" "$_pinned" "$_locked")"
    _out_arr="$(printf '%s' "$_out_arr" | jq --argjson r "$_row" '. + [$r]')"
  done <<< "$(mcp_catalogue_list_names)"

  printf '%s\n' "$_out_arr"
  exit 0
fi

# Table output.
printf '%-16s %-40s %-10s %-22s %-22s %-22s %-8s %s\n' \
  "NAME" "IMAGE" "PRESENT" "LOCAL" "PINNED" "WIRED" "DRIFT" "SIZE"
printf '%-16s %-40s %-10s %-22s %-22s %-22s %-8s %s\n' \
  "────────────────" "────────────────────────────────────────" "──────────" "──────────────────────" "──────────────────────" "──────────────────────" "────────" "────"

while IFS= read -r _mname; do
  [ -z "$_mname" ] && continue

  _kind="$(mcp_catalogue_get_field "$_mname" '.kind')"
  [ "$_kind" != "oci-image" ] && continue

  _image="$(mcp_catalogue_get_field "$_mname" '.source.image')"
  _pinned="$(mcp_catalogue_get "$_mname" \
    | jq -r '.versions.releases[.versions.pins.stable].digest // empty')"
  _locked="$(printf '%s' "$lock_json" \
    | jq -r --arg n "$_mname" '(.mcps // [])[] | select(.name == $n) | .integrity.value // ""')"

  _present="(n/a)"
  _local_disp="—"
  _pinned_disp="—"
  _wired_disp="—"
  _size="—"
  _local_full=""

  if [ -n "$_pinned" ]; then
    _pinned_disp="${_pinned:0:19}"
  fi

  if [ "$_docker_cli_ok" = "true" ] && [ "$_docker_daemon_ok" = "true" ]; then
    if [ -n "$_pinned" ]; then
      _full_ref="${_image}@${_pinned}"
      if atlas_aci_check_image "$_full_ref" 2>/dev/null; then
        _present="yes"

        _repo_digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "$_full_ref" 2>/dev/null || true)"
        if [ -n "$_repo_digest" ]; then
          _local_full="${_repo_digest##*@}"
          _local_disp="${_local_full:0:19}"
        fi

        _size_raw="$(docker image inspect --format '{{.Size}}' "$_full_ref" 2>/dev/null || true)"
        if [ -n "$_size_raw" ] && [ "$_size_raw" != "0" ]; then
          if [ "$_size_raw" -ge 1073741824 ] 2>/dev/null; then
            _size="$(( _size_raw / 1073741824 ))GB"
          elif [ "$_size_raw" -ge 1048576 ] 2>/dev/null; then
            _size="$(( _size_raw / 1048576 ))MB"
          elif [ "$_size_raw" -ge 1024 ] 2>/dev/null; then
            _size="$(( _size_raw / 1024 ))KB"
          else
            _size="${_size_raw}B"
          fi
        fi
      else
        _present="no"
      fi
    else
      _present="no"
    fi
  fi

  # WIRED / DRIFT (R10 / F3): wired-vs-locked, computed straight from
  # .mcp.json — no docker involved, unlike PRESENT/LOCAL/PINNED above.
  _wired_full="$(_mcp_oci_mcpjson_digest "$_mname" "$(pwd)" 2>/dev/null || true)"
  _drift="unknown"
  if [ -n "$_wired_full" ]; then
    _wired_disp="${_wired_full:0:19}"
    if [ -n "$_locked" ]; then
      if [ "$_wired_full" = "$_locked" ]; then
        _drift="no"
      else
        _drift="yes"
      fi
    fi
  fi

  printf '%-16s %-40s %-10s %-22s %-22s %-22s %-8s %s\n' \
    "$_mname" "$_image" "$_present" "$_local_disp" "$_pinned_disp" "$_wired_disp" "$_drift" "$_size"
done <<< "$(mcp_catalogue_list_names)"

exit 0
