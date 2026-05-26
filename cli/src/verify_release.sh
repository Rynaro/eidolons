#!/usr/bin/env bash
# eidolons verify-release — Layer 2 methodology integrity (functional re-derivation)
# ═══════════════════════════════════════════════════════════════════════════════════
#
# Compares every installed .eidolons/<name>/ tree against what a fresh install
# of the pinned upstream version would produce today. Reports OK / DRIFT /
# MISSING / EXTRA per file. install.manifest.json is excluded (timestamp drift
# is expected). Layer 1 = eidolons doctor --deep D4; Layer 2 = this subcommand.
#
# Bash 3.2 compatible: no associative arrays, no mapfile/readarray,
# no ${var,,}, no &>>, no process-substitution with exit-code dependence.

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

usage() {
  cat <<'EOF'
eidolons verify-release — Layer 2 methodology integrity: compare installed
Eidolon files against a fresh re-derivation from the upstream-pinned release.

Usage: eidolons verify-release [OPTIONS]

Options:
  --eidolon NAME    Verify only this Eidolon (repeatable).
  --strict          Exit non-zero on any drift (default: WARN-only, exit 0).
  --no-fetch        Use per-version cache only; do not fetch upstream.
  --json            Emit machine-readable JSON report on stdout.
  -h, --help        Show this help.

What it does:
  For each Eidolon in eidolons.lock, run its install.sh into a tmp dir,
  SHA-256 every file in the tmp install, and compare against the consumer's
  on-disk .eidolons/<name>/ tree. Reports OK / DRIFT / MISSING / EXTRA per
  file. install.manifest.json is excluded (timestamp drift is expected).

Catches:
  - Local file tampering after install
  - Mid-install corruption that fooled doctor --deep D4 (lock + files
    matched each other but both differ from upstream)
  - Accidentally deleted files under .eidolons/<name>/
  - Files added under .eidolons/<name>/ that aren't part of the install

Remediation:
  Drift is diagnostic only. To restore, run:
    eidolons sync                               # all members
    eidolons remove <name> && eidolons add <name>   # one member
EOF
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
TARGETS_LIST=""          # newline-separated, built from repeated --eidolon
STRICT=false
NO_FETCH=false
JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --eidolon)
      [[ $# -gt 1 ]] || die "Flag --eidolon requires a value"
      if [[ -z "$TARGETS_LIST" ]]; then
        TARGETS_LIST="$2"
      else
        TARGETS_LIST="$TARGETS_LIST"$'\n'"$2"
      fi
      shift 2
      ;;
    --strict)      STRICT=true;   shift ;;
    --no-fetch)    NO_FETCH=true; shift ;;
    --json)        JSON=true;     shift ;;
    -h|--help)     usage; exit 0 ;;
    *)
      printf '%s unknown flag: %s\n' "verify-release" "$1" >&2
      exit 2
      ;;
  esac
done

# ─── Require lock ─────────────────────────────────────────────────────────────
[[ -f "$PROJECT_LOCK" ]] || die "No eidolons.lock found. Run 'eidolons sync' first."

LOCK_JSON="$(yaml_to_json "$PROJECT_LOCK")"

# Validate and collect targets from lock.
ALL_LOCK_NAMES="$(printf '%s' "$LOCK_JSON" | jq -r '(.members // []) | map(.name) | .[]')"

if [[ -z "$ALL_LOCK_NAMES" ]]; then
  warn "No members in eidolons.lock"
  exit 0
fi

if [[ -z "$TARGETS_LIST" ]]; then
  TARGETS_LIST="$ALL_LOCK_NAMES"
else
  # Validate each requested name against lock.
  while IFS= read -r _req; do
    [[ -z "$_req" ]] && continue
    if ! printf '%s\n' "$ALL_LOCK_NAMES" | grep -Fxq "$_req"; then
      _avail="$(printf '%s\n' "$ALL_LOCK_NAMES" | tr '\n' ' ' | sed 's/ $//')"
      die "$_req is not in eidolons.lock. Available: $_avail"
    fi
  done <<< "$TARGETS_LIST"
fi

# ─── Resolve project manifest config (hosts.wire + shared_dispatch) ──────────
HOSTS_CSV=""
SHARED_DISPATCH="false"
if [[ -f "$PROJECT_MANIFEST" ]]; then
  _manifest_json="$(yaml_to_json "$PROJECT_MANIFEST")"
  HOSTS_CSV="$(printf '%s' "$_manifest_json" | jq -r '.hosts.wire // [] | join(",")')"
  SHARED_DISPATCH="$(printf '%s' "$_manifest_json" | jq -r '.hosts.shared_dispatch // false')"
fi

# ─── Nexus refresh ─────────────────────────────────────────────────────────────
nexus_refresh

# ─── sha_tree_diff TMP_ROOT CONSUMER_ROOT ────────────────────────────────────
# Echoes one line per non-OK path on stdout:
#   <STATUS><TAB><relpath><TAB><tmp_sha><TAB><consumer_sha>
# Status in {DIFFER, MISSING, EXTRA}. OK paths suppressed.
# Bash 3.2 compatible: no associative arrays, no readarray.
sha_tree_diff() {
  local tmp_root="$1" consumer_root="$2"
  local tmp_list="" consumer_list=""

  if [[ -d "$tmp_root" ]]; then
    tmp_list="$(cd "$tmp_root" && find . -type f \
      -not -name install.manifest.json \
      -not -name '*.tmp' -not -name '*.bak' -not -name '*.swp' \
      | sed 's|^\./||' | sort)"
  fi

  if [[ -d "$consumer_root" ]]; then
    consumer_list="$(cd "$consumer_root" && find . -type f \
      -not -name install.manifest.json \
      -not -name '*.tmp' -not -name '*.bak' -not -name '*.swp' \
      | sed 's|^\./||' | sort)"
  fi

  # Pass 1: iterate tmp files — check DIFFER vs MISSING (file missing on consumer).
  if [[ -n "$tmp_list" ]]; then
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      if [[ -f "$consumer_root/$p" ]]; then
        local tmp_sha cons_sha
        tmp_sha="$(sha256_file "$tmp_root/$p")"
        cons_sha="$(sha256_file "$consumer_root/$p")"
        if [[ "$tmp_sha" != "$cons_sha" ]]; then
          printf 'DIFFER\t%s\t%s\t%s\n' "$p" "$tmp_sha" "$cons_sha"
        fi
      else
        printf 'MISSING\t%s\t%s\t-\n' "$p" "$(sha256_file "$tmp_root/$p")"
      fi
    done <<< "$tmp_list"
  fi

  # Pass 2: iterate consumer files — check EXTRA (file not produced by installer).
  if [[ -n "$consumer_list" ]]; then
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      if [[ ! -f "$tmp_root/$p" ]]; then
        printf 'EXTRA\t%s\t-\t%s\n' "$p" "$(sha256_file "$consumer_root/$p")"
      fi
    done <<< "$consumer_list"
  fi
}

# ─── Trap: top-level tmp dir cleanup ──────────────────────────────────────────
_VR_TMP_ROOTS=""
_vr_cleanup() {
  local _t
  if [[ -n "$_VR_TMP_ROOTS" ]]; then
    while IFS= read -r _t; do
      [[ -n "$_t" ]] && rm -rf "$_t" 2>/dev/null || true
    done <<< "$_VR_TMP_ROOTS"
  fi
}
trap '_vr_cleanup' EXIT

# ─── Per-member state (parallel arrays, Bash 3.2) ────────────────────────────
_member_names=""    # newline-separated
_member_versions="" # newline-separated (same order)
_member_statuses="" # newline-separated: ok|drift|error
_member_counts=""   # newline-separated: file count (tmp)
_member_diffs=""    # newline-separated blobs (TAB-separated); "NONE" when empty

_total_verified=0
_total_drifted=0
_total_errors=0
_any_drift=false

# ─── Main loop ────────────────────────────────────────────────────────────────
while IFS= read -r name; do
  [[ -z "$name" ]] && continue

  version="$(lock_member_version "$name")"

  if [[ -z "$version" ]]; then
    warn "verify-release: $name has no version in lock — skipping"
    _total_errors=$((_total_errors + 1))
    continue
  fi

  # ── Cache resolution ─────────────────────────────────────────────────────
  cache_dir="$CACHE_DIR/$name@$version"
  if [[ ! -d "$cache_dir/.git" ]]; then
    if [[ "$NO_FETCH" == "true" ]]; then
      die "Cache for $name@$version missing. Run without --no-fetch, or run 'eidolons sync' first."
    fi
    cache_dir="$(fetch_eidolon "$name" "$version")"
  fi

  # ── Create tmp install target ────────────────────────────────────────────
  tmp_root="$(mktemp -d "/tmp/verify-release-$name-XXXXXX")"
  _VR_TMP_ROOTS="$_VR_TMP_ROOTS"$'\n'"$tmp_root"
  tmp_target="$tmp_root/.eidolons/$name"
  mkdir -p "$tmp_target"

  # ── Run installer ────────────────────────────────────────────────────────
  if [[ ! -x "$cache_dir/install.sh" ]]; then
    warn "verify-release: $name@$version has no executable install.sh — cannot re-derive"
    _total_errors=$((_total_errors + 1))
    continue
  fi

  # Mirror sync.sh's shared-dispatch flag logic.
  shared_flag_args=""
  if grep -q -- '--no-shared-dispatch' "$cache_dir/install.sh" 2>/dev/null; then
    if [[ "$SHARED_DISPATCH" == "true" ]]; then
      shared_flag_args="--shared-dispatch"
    else
      shared_flag_args="--no-shared-dispatch"
    fi
  fi

  _install_ok=true
  if [[ -n "$shared_flag_args" ]]; then
    run_installer_captured "$name" "${VERBOSITY:-default}" "$cache_dir" \
      --target "$tmp_target" \
      --hosts "$HOSTS_CSV" \
      $shared_flag_args \
      --non-interactive \
      --force \
      || { _install_ok=false; true; }
  else
    run_installer_captured "$name" "${VERBOSITY:-default}" "$cache_dir" \
      --target "$tmp_target" \
      --hosts "$HOSTS_CSV" \
      --non-interactive \
      --force \
      || { _install_ok=false; true; }
  fi

  if [[ "$_install_ok" == "false" ]]; then
    die "install.sh for $name@$version failed during re-derivation (re-run with EIDOLONS_VERBOSE=1 for details)"
  fi

  # ── Tree diff ────────────────────────────────────────────────────────────
  consumer_root="./.eidolons/$name"
  consumer_absent=false
  if [[ ! -d "$consumer_root" ]]; then
    consumer_absent=true
  fi

  diff_output="$(sha_tree_diff "$tmp_target" "$consumer_root")"

  # Count files (from tmp install, excluding manifest/transient).
  file_count=0
  if [[ -d "$tmp_target" ]]; then
    file_count="$(cd "$tmp_target" && find . -type f \
      -not -name install.manifest.json \
      -not -name '*.tmp' -not -name '*.bak' -not -name '*.swp' \
      | wc -l | tr -d ' ')"
  fi

  # Classify member status.
  drift_count=0
  if [[ -n "$diff_output" ]]; then
    drift_count="$(printf '%s\n' "$diff_output" | grep -c '.' || true)"
  fi

  member_status="ok"
  if [[ "$consumer_absent" == "true" ]]; then
    member_status="drift"
    _any_drift=true
    _total_drifted=$((_total_drifted + 1))
  elif [[ "$drift_count" -gt 0 ]]; then
    member_status="drift"
    _any_drift=true
    _total_drifted=$((_total_drifted + 1))
  else
    _total_verified=$((_total_verified + 1))
  fi

  # ── Human-readable per-member report (to stderr, unless --json) ──────────
  if [[ "$JSON" != "true" ]]; then
    if [[ "$member_status" == "ok" ]]; then
      ok "$name@$version  ($file_count files, 0 drift)"
    else
      if [[ "$consumer_absent" == "true" ]]; then
        warn "$name@$version (.eidolons/$name/ absent — run 'eidolons sync')"
      else
        warn "$name@$version  ($file_count files, $drift_count drift)"
      fi
      if [[ -n "$diff_output" ]]; then
        while IFS= read -r _line; do
          [[ -z "$_line" ]] && continue
          _status="$(printf '%s' "$_line" | cut -f1)"
          _path="$(printf '%s' "$_line" | cut -f2)"
          _sha1="$(printf '%s' "$_line" | cut -f3)"
          _sha2="$(printf '%s' "$_line" | cut -f4)"
          printf '    %-10s %s\n' "$_status" "$_path" >&2
          case "$_status" in
            DIFFER)
              printf '                 tmp:      %s\n' "$_sha1" >&2
              printf '                 consumer: %s\n' "$_sha2" >&2
              ;;
            MISSING)
              printf '                 (not present on consumer; upstream sha: %s)\n' "$_sha1" >&2
              ;;
            EXTRA)
              printf '                 consumer: %s\n' "$_sha2" >&2
              ;;
          esac
        done <<< "$diff_output"
      fi
    fi
  fi

  # ── Accumulate parallel arrays ────────────────────────────────────────────
  if [[ -z "$_member_names" ]]; then
    _member_names="$name"
    _member_versions="$version"
    _member_statuses="$member_status"
    _member_counts="$file_count"
    _member_diffs="${diff_output:-NONE}"
  else
    _member_names="$_member_names"$'\n'"$name"
    _member_versions="$_member_versions"$'\n'"$version"
    _member_statuses="$_member_statuses"$'\n'"$member_status"
    _member_counts="$_member_counts"$'\n'"$file_count"
    _member_diffs="$_member_diffs"$'\n'"${diff_output:-NONE}"
  fi

done <<< "$TARGETS_LIST"

# ─── Aggregate footer (human mode) ────────────────────────────────────────────
if [[ "$JSON" != "true" ]]; then
  printf '\nverify-release summary: %d verified, %d drift, %d errors\n' \
    "$_total_verified" "$_total_drifted" "$_total_errors" >&2

  if [[ "$_any_drift" == "true" ]] || [[ "$_total_errors" -gt 0 ]]; then
    printf 'Remediation: run '\''eidolons sync'\'' to restore.\n' >&2
  fi
fi

# ─── JSON output (stdout only) ────────────────────────────────────────────────
if [[ "$JSON" == "true" ]]; then
  _version_str="${EIDOLONS_VERSION:-0.0.0-dev}"
  _checked_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")"
  _strict_json="false"
  [[ "$STRICT" == "true" ]] && _strict_json="true"

  # Build members JSON array. Walk parallel arrays line by line.
  _members_json_arr="["
  _first_member=true

  # We need to iterate the accumulated parallel arrays in sync.
  # Since they're newline-separated strings and Bash 3.2 has no zip,
  # we use line numbers via a helper counter.
  _line_idx=0
  _names_arr=""
  _versions_arr=""
  _statuses_arr=""
  _counts_arr=""

  # Populate via indexed substitution using printf+head.
  _total_lines=0
  if [[ -n "$_member_names" ]]; then
    _total_lines="$(printf '%s\n' "$_member_names" | wc -l | tr -d ' ')"
  fi

  _lnum=1
  while [[ "$_lnum" -le "$_total_lines" ]]; do
    _mn="$(printf '%s\n' "$_member_names" | sed -n "${_lnum}p")"
    _mv="$(printf '%s\n' "$_member_versions" | sed -n "${_lnum}p")"
    _ms="$(printf '%s\n' "$_member_statuses" | sed -n "${_lnum}p")"
    _mc="$(printf '%s\n' "$_member_counts" | sed -n "${_lnum}p")"
    _md="$(printf '%s\n' "$_member_diffs" | sed -n "${_lnum}p")"

    # Build diff array for this member.
    _diff_json_arr="["
    _first_diff=true
    if [[ "$_md" != "NONE" && -n "$_md" ]]; then
      while IFS= read -r _dl; do
        [[ -z "$_dl" ]] && continue
        _ds="$(printf '%s' "$_dl" | cut -f1)"
        _dp="$(printf '%s' "$_dl" | cut -f2)"
        _d1="$(printf '%s' "$_dl" | cut -f3)"
        _d2="$(printf '%s' "$_dl" | cut -f4)"
        _tmp_sha_json="null"
        _con_sha_json="null"
        [[ "$_d1" != "-" ]] && _tmp_sha_json="\"$_d1\""
        [[ "$_d2" != "-" ]] && _con_sha_json="\"$_d2\""
        if [[ "$_first_diff" == "true" ]]; then
          _first_diff=false
        else
          _diff_json_arr="$_diff_json_arr,"
        fi
        _diff_json_arr="${_diff_json_arr}{\"status\":\"$_ds\",\"path\":\"$_dp\",\"tmp_sha\":$_tmp_sha_json,\"consumer_sha\":$_con_sha_json}"
      done <<< "$_md"
    fi
    _diff_json_arr="$_diff_json_arr]"

    if [[ "$_first_member" == "true" ]]; then
      _first_member=false
    else
      _members_json_arr="$_members_json_arr,"
    fi
    _members_json_arr="${_members_json_arr}{\"name\":\"$_mn\",\"version\":\"$_mv\",\"status\":\"$_ms\",\"file_count\":$_mc,\"diff\":$_diff_json_arr}"

    _lnum=$((_lnum + 1))
  done

  _members_json_arr="$_members_json_arr]"

  # Emit the JSON object to stdout.
  printf '{"cli_version":"%s","checked_at":"%s","strict":%s,"summary":{"verified":%d,"drifted":%d,"errors":%d},"members":%s}\n' \
    "$_version_str" \
    "$_checked_at" \
    "$_strict_json" \
    "$_total_verified" \
    "$_total_drifted" \
    "$_total_errors" \
    "$_members_json_arr"
fi

# ─── Exit code ────────────────────────────────────────────────────────────────
if [[ "$STRICT" == "true" ]] && ( [[ "$_any_drift" == "true" ]] || [[ "$_total_errors" -gt 0 ]] ); then
  exit 1
fi
exit 0
