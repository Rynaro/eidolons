#!/usr/bin/env bash
# cli/src/lib_mcp.sh — shared helpers for eidolons mcp subcommands.
#
# SOURCE this file; do NOT execute it directly.
# Requires lib.sh to have been sourced first (for yaml_to_json, CACHE_DIR, etc.)
#
# Exported helpers:
#   mcp_catalogue_file          → path to roster/mcps.yaml
#   mcp_lockfile                → path to eidolons.mcp.lock (project-local)
#   mcp_catalogue_list_names    → one name per line
#   mcp_catalogue_get NAME      → JSON object for that MCP (or empty)
#   mcp_lock_read               → JSON string of the full lockfile (or '{}')
#   mcp_lock_entry NAME         → JSON for one lock entry (or empty)
#   mcp_lock_upsert NAME JSON   → atomically upsert one entry; sorts by name
#   mcp_lock_remove NAME        → remove one entry; re-write the lockfile
#   mcp_lock_write JSON_ARRAY   → write a full mcps[] array (sorted); preserves installed_at
#
# Driver protocol (kind-switch):
#   mcp_driver_oci_image_install   NAME VERSION [--force] [--project-root PATH]
#   mcp_driver_oci_image_refresh   NAME VERSION
#   mcp_driver_oci_image_uninstall NAME [--project-root PATH]
#   mcp_driver_oci_image_version   NAME  → installed version to stdout (or empty)
#   mcp_driver_oci_image_health    NAME  → status lines to stdout; exit 0 always
#
#   mcp_driver_binary_install      NAME VERSION [--force]
#   mcp_driver_binary_refresh      NAME VERSION
#   mcp_driver_binary_uninstall    NAME
#   mcp_driver_binary_version      NAME  → installed version to stdout (or empty)
#   mcp_driver_binary_health       NAME  → status lines to stdout; exit 0 always
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

# Guard against double-source.
if [ -n "${_LIB_MCP_LOADED:-}" ]; then
  return 0
fi
_LIB_MCP_LOADED=1

# Source lib_mcp_atlas_aci.sh for the oci-image driver helpers.
# SELF_DIR may not be set here since this is sourced; derive from BASH_SOURCE.
_LIB_MCP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_LIB_MCP_DIR/lib_mcp_atlas_aci.sh"

# ─── Paths ────────────────────────────────────────────────────────────────────
mcp_catalogue_file() {
  echo "$NEXUS/roster/mcps.yaml"
}

mcp_lockfile() {
  echo "./eidolons.mcp.lock"
}

# ─── Catalogue helpers ────────────────────────────────────────────────────────

# mcp_catalogue_list_names — list catalogue MCP names, one per line.
mcp_catalogue_list_names() {
  local cat_file
  cat_file="$(mcp_catalogue_file)"
  if [ ! -f "$cat_file" ]; then
    return 0
  fi
  yaml_to_json "$cat_file" | jq -r '.mcps[].name'
}

# mcp_catalogue_get NAME — emit JSON for one catalogue entry (or empty on miss).
mcp_catalogue_get() {
  local name="$1"
  local cat_file
  cat_file="$(mcp_catalogue_file)"
  if [ ! -f "$cat_file" ]; then
    return 0
  fi
  yaml_to_json "$cat_file" \
    | jq --arg n "$name" '.mcps[] | select(.name == $n)'
}

# mcp_catalogue_get_field NAME JQPATH — emit one field from a catalogue entry.
mcp_catalogue_get_field() {
  local name="$1" field="$2"
  mcp_catalogue_get "$name" | jq -r "$field // empty"
}

# ─── Lockfile helpers ─────────────────────────────────────────────────────────

# mcp_lock_read — emit the full lockfile as JSON; '{}' when absent or unreadable.
mcp_lock_read() {
  local lf
  lf="$(mcp_lockfile)"
  if [ ! -f "$lf" ]; then
    echo '{}'
    return 0
  fi
  yaml_to_json "$lf" 2>/dev/null || echo '{}'
}

# mcp_lock_entry NAME — emit the JSON object for one installed MCP; empty on miss.
mcp_lock_entry() {
  local name="$1"
  mcp_lock_read \
    | jq --arg n "$name" '(.mcps // [])[] | select(.name == $n)'
}

# _mcp_now — current UTC timestamp in RFC 3339 / ISO 8601 format.
# Bash 3.2 safe: uses 'date -u'.
_mcp_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# _mcp_cli_version — read from VERSION file or fallback.
_mcp_cli_version() {
  local _vf="$NEXUS/VERSION"
  if [ -f "$_vf" ]; then
    tr -d '[:space:]' < "$_vf"
  else
    echo "0.0.0-dev"
  fi
}

# mcp_lock_write_from_array JSON_ARRAY_STR — write the lockfile from a JSON array
# of mcp entries. Sorts entries by name. Preserves installed_at for entries whose
# other fields (kind, version, source, integrity, target) are unchanged.
#
# This is the canonical write path. All other writes funnel through here to
# guarantee sorted, deterministic output (F3.4 invariant).
mcp_lock_write_from_array() {
  local new_arr="$1"
  local lf generated cat_ver cli_ver

  lf="$(mcp_lockfile)"
  generated="$(_mcp_now)"
  cat_ver="$(yaml_to_json "$(mcp_catalogue_file)" 2>/dev/null \
    | jq -r '.catalogue_version // "1.0"' 2>/dev/null || echo '1.0')"
  cli_ver="$(_mcp_cli_version)"

  # Sort array by name (lexicographic) and write as YAML.
  # We write YAML manually because yq write is not a hard dep at runtime.
  local sorted_json
  sorted_json="$(printf '%s' "$new_arr" \
    | jq 'sort_by(.name) | map(.hosts_wired |= sort)')"

  # Build the lockfile in a tmpfile first, then atomically replace.
  local tmpfile
  tmpfile="$(mktemp)"

  {
    printf '# eidolons.mcp.lock — auto-generated by '\''eidolons mcp install/upgrade/sync'\''. Commit to VCS.\n'
    printf 'generated_at: "%s"\n' "$generated"
    printf 'eidolons_cli_version: "%s"\n' "$cli_ver"
    printf 'catalogue_version: "%s"\n' "$cat_ver"
    printf 'mcps:\n'

    printf '%s' "$sorted_json" | jq -c '.[]' | while IFS= read -r entry; do
      local ename ekind eversion
      ename="$(printf '%s' "$entry" | jq -r '.name')"
      ekind="$(printf '%s' "$entry" | jq -r '.kind')"
      eversion="$(printf '%s' "$entry" | jq -r '.version')"
      einstalled="$(printf '%s' "$entry" | jq -r '.installed_at')"
      etarget="$(printf '%s' "$entry" | jq -r '.target // ""')"
      eintegrity_algo="$(printf '%s' "$entry" | jq -r '.integrity.algo // "none"')"
      eintegrity_val="$(printf '%s' "$entry" | jq -r '.integrity.value // ""')"

      printf '  - name: %s\n' "$ename"
      printf '    kind: %s\n' "$ekind"
      printf '    version: "%s"\n' "$eversion"

      # source block (kind-specific)
      local esrc_image esrc_repo esrc_url
      esrc_image="$(printf '%s' "$entry" | jq -r '.source.image // ""')"
      esrc_repo="$(printf '%s' "$entry" | jq -r '.source.repo // ""')"
      esrc_url="$(printf '%s' "$entry" | jq -r '.source.url // ""')"
      printf '    source:\n'
      if [ -n "$esrc_image" ]; then
        printf '      image: "%s"\n' "$esrc_image"
      fi
      if [ -n "$esrc_repo" ]; then
        printf '      repo: "%s"\n' "$esrc_repo"
      fi
      if [ -n "$esrc_url" ]; then
        printf '      url: "%s"\n' "$esrc_url"
      fi

      # integrity block
      printf '    integrity:\n'
      printf '      algo: %s\n' "$eintegrity_algo"
      printf '      value: "%s"\n' "$eintegrity_val"

      # target
      if [ -n "$etarget" ]; then
        printf '    target: "%s"\n' "$etarget"
      fi

      # hosts_wired
      local ehosts
      ehosts="$(printf '%s' "$entry" | jq -r '(.hosts_wired // [])[]')"
      if [ -n "$ehosts" ]; then
        printf '    hosts_wired:\n'
        while IFS= read -r hw; do
          [ -n "$hw" ] && printf '      - "%s"\n' "$hw"
        done <<< "$ehosts"
      fi

      printf '    installed_at: "%s"\n' "$einstalled"
    done
  } > "$tmpfile"

  mv "$tmpfile" "$lf"
}

# mcp_lock_upsert NAME ENTRY_JSON
# Insert or update one entry in the lockfile. Preserves installed_at if the
# entry is otherwise unchanged (idempotency: F3.4 invariant).
mcp_lock_upsert() {
  local name="$1"
  local new_entry="$2"

  local existing_arr
  existing_arr="$(mcp_lock_read | jq '(.mcps // [])')"

  # Check if entry exists and if it's changed.
  local old_entry
  old_entry="$(printf '%s' "$existing_arr" \
    | jq --arg n "$name" '.[] | select(.name == $n)')"

  local new_entry_final
  if [ -n "$old_entry" ]; then
    # Compare fields that matter for idempotency (all except installed_at).
    local old_sig new_sig
    old_sig="$(printf '%s' "$old_entry" \
      | jq -c '{kind,version,source,integrity,target,hosts_wired}')"
    new_sig="$(printf '%s' "$new_entry" \
      | jq -c '{kind,version,source,integrity,target,hosts_wired}')"

    if [ "$old_sig" = "$new_sig" ]; then
      # No-op: preserve the original installed_at. Skip write.
      return 0
    fi

    # Changed: preserve name but update installed_at.
    new_entry_final="$new_entry"
  else
    new_entry_final="$new_entry"
  fi

  # Build the new array: remove the old entry (if any) and add the new one.
  local new_arr
  new_arr="$(printf '%s' "$existing_arr" \
    | jq --arg n "$name" 'map(select(.name != $n))')"
  new_arr="$(printf '%s' "$new_arr" \
    | jq --argjson e "$new_entry_final" '. + [$e]')"

  mcp_lock_write_from_array "$new_arr"
}

# mcp_lock_remove NAME — remove an entry from the lockfile.
mcp_lock_remove() {
  local name="$1"
  local lf
  lf="$(mcp_lockfile)"

  if [ ! -f "$lf" ]; then
    return 0
  fi

  local new_arr
  new_arr="$(mcp_lock_read | jq --arg n "$name" '(.mcps // []) | map(select(.name != $n))')"

  if [ "$(printf '%s' "$new_arr" | jq 'length')" -eq 0 ]; then
    # Last entry removed — delete the lockfile rather than leaving an empty one.
    rm -f "$lf"
    return 0
  fi

  mcp_lock_write_from_array "$new_arr"
}

# ─── oci-image driver ─────────────────────────────────────────────────────────

# mcp_driver_oci_image_install NAME VERSION [--force] [--project-root PATH]
# Wraps mcp_atlas_aci.sh logic (resolves digest, runs docker pre-flight, renders
# .mcp.json from template, upserts lockfile entry).
mcp_driver_oci_image_install() {
  local name="$1"
  local version="$2"
  shift 2

  local force=false
  local project_root=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --force)         force=true; shift ;;
      --project-root)  project_root="$2"; shift 2 ;;
      *)               warn "mcp_driver_oci_image_install: unknown option $1"; shift ;;
    esac
  done

  project_root="${project_root:-$(pwd)}"

  # Build mcp_atlas_aci.sh args.
  local aci_args=""
  if [ "$force" = "true" ]; then
    aci_args="--force"
  fi

  # Get the digest for the requested version from catalogue.
  local digest
  digest="$(mcp_catalogue_get "$name" \
    | jq -r --arg v "$version" '.versions.releases[$v].digest // empty')"

  local extra_args=""
  if [ -n "$digest" ]; then
    extra_args="--image-digest $digest"
  fi

  # Invoke the existing atlas-aci generator.
  # shellcheck disable=SC1091
  bash "$_LIB_MCP_DIR/mcp_atlas_aci.sh" \
    --project-root "$project_root" \
    ${aci_args:+$aci_args} \
    ${extra_args:+$extra_args} || return $?

  # Build lockfile entry.
  local source_image installed_at hosts_wired
  source_image="$(mcp_catalogue_get_field "$name" '.source.image')"
  installed_at="$(_mcp_now)"
  hosts_wired='[".mcp.json",".cursor/mcp.json",".github/agents/*",".codex/config.toml"]'

  local entry
  entry="$(jq -n \
    --arg nm "$name" \
    --arg kd "oci-image" \
    --arg ver "$version" \
    --arg img "$source_image" \
    --arg algo "oci-digest" \
    --arg digv "${digest:-}" \
    --arg tgt ".mcp.json" \
    --argjson hw "$hosts_wired" \
    --arg iat "$installed_at" \
    '{
      name: $nm,
      kind: $kd,
      version: $ver,
      source: {image: $img},
      integrity: {algo: $algo, value: $digv},
      target: $tgt,
      hosts_wired: $hw,
      installed_at: $iat
    }')"

  mcp_lock_upsert "$name" "$entry"
}

# mcp_driver_oci_image_refresh NAME VERSION
# Re-pull the image at the locked digest. Does NOT regenerate .mcp.json.
# Updates installed_at in the lockfile.
mcp_driver_oci_image_refresh() {
  local name="$1"
  local version="$2"

  # Get locked digest (prefer lockfile, fallback to catalogue).
  local digest
  digest="$(mcp_lock_entry "$name" | jq -r '.integrity.value // empty')"
  if [ -z "$digest" ]; then
    digest="$(mcp_catalogue_get "$name" \
      | jq -r --arg v "$version" '.versions.releases[$v].digest // empty')"
  fi

  local source_image
  source_image="$(mcp_catalogue_get_field "$name" '.source.image')"
  local full_ref="${source_image}@${digest}"

  # Run docker pre-flight.
  if ! atlas_aci_check_docker_cli; then return 1; fi
  if ! atlas_aci_check_docker_daemon; then return 1; fi

  say "Refreshing image: $full_ref"
  if ! atlas_aci_check_image "$full_ref" 2>/dev/null; then
    bash "$_LIB_MCP_DIR/mcp_atlas_aci_pull.sh" \
      --image-digest "$digest" || return $?
  else
    info "Image already present, confirming..."
  fi

  # Update installed_at to mark refresh.
  local old_entry installed_at
  old_entry="$(mcp_lock_entry "$name")"
  installed_at="$(_mcp_now)"
  if [ -n "$old_entry" ]; then
    local updated
    updated="$(printf '%s' "$old_entry" \
      | jq --arg iat "$installed_at" '.installed_at = $iat')"
    # Force-update the lockfile even if no other field changed.
    local existing_arr new_arr
    existing_arr="$(mcp_lock_read | jq '(.mcps // [])')"
    new_arr="$(printf '%s' "$existing_arr" \
      | jq --arg n "$name" 'map(select(.name != $n))')"
    new_arr="$(printf '%s' "$new_arr" \
      | jq --argjson e "$updated" '. + [$e]')"
    mcp_lock_write_from_array "$new_arr"
  fi

  ok "atlas-aci refresh complete"
}

# mcp_driver_oci_image_uninstall NAME [--project-root PATH]
# Remove marker-bounded sections for atlas-aci from host files. Does NOT
# delete the Docker image or .atlas/memex/codegraph.db.
mcp_driver_oci_image_uninstall() {
  local name="$1"
  shift

  local project_root=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project-root)  project_root="$2"; shift 2 ;;
      *)               shift ;;
    esac
  done

  project_root="${project_root:-$(pwd)}"

  # Check if installed at all.
  local entry
  entry="$(mcp_lock_entry "$name")"
  if [ -z "$entry" ]; then
    info "${name} not installed (nothing to remove)"
    return 0
  fi

  # Remove the marker key from .mcp.json (if it exists and is valid JSON).
  local mcp_json="${project_root}/.mcp.json"
  if [ -f "$mcp_json" ] && command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    if jq 'del(.mcpServers["'"${name}"'"])' "$mcp_json" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$mcp_json"
      info "Removed ${name} from .mcp.json"
    else
      rm -f "$tmp"
      warn "Could not parse .mcp.json — manual cleanup may be required"
    fi
    # Remove the _eidolon sentinel key if atlas-aci was the last entry.
    local remaining
    remaining="$(jq '.mcpServers | length' "$mcp_json" 2>/dev/null || echo 0)"
    if [ "$remaining" -eq 0 ]; then
      info ".mcp.json now has no MCP servers; leaving the empty shell"
    fi
  fi

  # Remove from .cursor/mcp.json if present.
  local cursor_mcp="${project_root}/.cursor/mcp.json"
  if [ -f "$cursor_mcp" ] && command -v jq >/dev/null 2>&1; then
    local tmp2
    tmp2="$(mktemp)"
    if jq 'del(.mcpServers["'"${name}"'"])' "$cursor_mcp" > "$tmp2" 2>/dev/null; then
      mv "$tmp2" "$cursor_mcp"
      info "Removed ${name} from .cursor/mcp.json"
    else
      rm -f "$tmp2"
    fi
  fi

  # Remove lockfile entry.
  mcp_lock_remove "$name"
  ok "${name} uninstalled"
}

# mcp_driver_oci_image_version NAME → installed version (from lockfile) to stdout.
mcp_driver_oci_image_version() {
  local name="$1"
  mcp_lock_entry "$name" | jq -r '.version // empty'
}

# _mcp_driver_oci_uid_bind_probes NAME → UID/GID and bind-path probe lines to stdout.
#
# Reads .mcp.json in CWD. If absent, malformed, or missing the atlas-aci key,
# this function silently no-ops (zero output, exit 0). This preserves the
# D-T3.6/D-T3.7/D-T3.8 semantics.
#
# When the atlas-aci entry is found, three probe classes run:
#
#   mcp_uid_pin  ok    — -u UID:GID present and matches id -u:id -g
#   mcp_uid_pin  err   — -u UID:GID present but mismatches current user
#   mcp_uid_pin  warn  — no -u flag at all (includes the 'eidolons atlas aci wire' hint)
#
#   mcp_bind_path_exists     err — a -v host:container arg's host path does not exist
#   mcp_bind_path_readable   err — host path exists but is not readable
#
# Output format per probe: "<name>  <probe>  ok|err|warn  [reason]"
# Callers that increment error counters should filter on status word "err";
# callers that surface warnings should filter on "warn".
#
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile.
_mcp_driver_oci_uid_bind_probes() {
  local name="$1"

  # Require jq; if absent caller can't parse JSON anyway.
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi

  # .mcp.json must exist in CWD.
  if [ ! -f ".mcp.json" ]; then
    return 0
  fi

  # Check that atlas-aci key exists and has an args array.
  # jq -e exits non-zero when the value is null/false/missing.
  if ! jq -e '.mcpServers["atlas-aci"].args | arrays' .mcp.json >/dev/null 2>&1; then
    # Malformed JSON, no mcpServers, or no atlas-aci key — silent skip.
    return 0
  fi

  # ── probe: mcp_uid_pin ──────────────────────────────────────────────────
  # Find the value following "-u" in the args array.
  # Strategy: to_entries on the args array, select entries whose value is "-u",
  # then return $arr at (key+1) — that's the UID:GID value.
  local _pinned_uid_gid
  _pinned_uid_gid="$(jq -r '
    .mcpServers["atlas-aci"].args as $arr
    | $arr | to_entries
    | map(select(.value == "-u") | .key + 1)
    | map($arr[.])
    | .[0] // empty
  ' .mcp.json 2>/dev/null || true)"

  local _cur_uid _cur_gid _cur_uidgid
  _cur_uid="$(id -u)"
  _cur_gid="$(id -g)"
  _cur_uidgid="${_cur_uid}:${_cur_gid}"

  if [ -z "$_pinned_uid_gid" ]; then
    # No -u flag at all.
    printf '%s  mcp_uid_pin       warn      no -u UID:GID pin in .mcp.json — re-run '"'"'eidolons atlas aci wire'"'"' to rebuild with current UID:GID\n' "$name"
  elif [ "$_pinned_uid_gid" = "$_cur_uidgid" ]; then
    printf '%s  mcp_uid_pin       ok\n' "$name"
  else
    printf '%s  mcp_uid_pin       err       pins --user %s but current user is %s\n' \
      "$name" "$_pinned_uid_gid" "$_cur_uidgid"
  fi

  # ── probe: mcp_bind_path_exists / mcp_bind_path_readable ───────────────
  # Collect host paths from all -v <host>:<container> args.
  # Strategy: to_entries on args, select entries whose value is "-v",
  # return $arr at (key+1) — that's the host:container bind spec.
  local _bind_specs _bspec _host_path
  _bind_specs="$(jq -r '
    .mcpServers["atlas-aci"].args as $arr
    | $arr | to_entries
    | map(select(.value == "-v") | .key + 1)
    | map($arr[.])
    | .[]
  ' .mcp.json 2>/dev/null || true)"

  if [ -n "$_bind_specs" ]; then
    while IFS= read -r _bspec; do
      [ -n "$_bspec" ] || continue
      # host_path is everything before the first colon.
      _host_path="${_bspec%%:*}"
      [ -n "$_host_path" ] || continue

      if [ ! -e "$_host_path" ]; then
        printf '%s  mcp_bind_path_exists      err   %s does not exist\n' \
          "$name" "$_host_path"
      elif [ ! -r "$_host_path" ]; then
        printf '%s  mcp_bind_path_readable    err   %s is not readable by current user\n' \
          "$name" "$_host_path"
      fi
    done <<< "$_bind_specs"
  fi

  return 0
}

# mcp_driver_oci_image_health NAME → probe status lines to stdout; exit 0 always.
# Output format per line: "<name>  <probe>  ok|degraded|missing  [reason]"
# New UID/GID and bind-path probes (mcp_uid_pin, mcp_bind_path_exists,
# mcp_bind_path_readable) use err|warn|ok status words and run when .mcp.json
# exists with an atlas-aci key. They fire after image_local and before
# registry_reachable. Callers should scan per-probe lines for err/warn.
mcp_driver_oci_image_health() {
  local name="$1"
  local overall="ok"

  # probe: docker_cli
  local cli_rc=0
  atlas_aci_check_docker_cli 2>/dev/null || cli_rc=$?
  if [ "$cli_rc" -eq 0 ]; then
    printf '%s  docker_cli       ok\n' "$name"
  else
    printf '%s  docker_cli       missing   docker not on PATH\n' "$name"
    overall="missing"
  fi

  # probe: docker_daemon (only if cli present)
  if [ "$cli_rc" -eq 0 ]; then
    local daemon_rc=0
    atlas_aci_check_docker_daemon 2>/dev/null || daemon_rc=$?
    if [ "$daemon_rc" -eq 0 ]; then
      printf '%s  docker_daemon    ok\n' "$name"
    else
      printf '%s  docker_daemon    degraded  docker daemon unreachable\n' "$name"
      overall="degraded"
    fi

    # probe: image_local (only if daemon reachable)
    if [ "$daemon_rc" -eq 0 ]; then
      local digest source_image locked_entry
      locked_entry="$(mcp_lock_entry "$name")"
      digest="$(printf '%s' "$locked_entry" | jq -r '.integrity.value // empty')"
      source_image="$(printf '%s' "$locked_entry" | jq -r '.source.image // empty')"

      if [ -n "$source_image" ] && [ -n "$digest" ]; then
        local full_ref="${source_image}@${digest}"
        local image_rc=0
        atlas_aci_check_image "$full_ref" 2>/dev/null || image_rc=$?
        if [ "$image_rc" -eq 0 ]; then
          printf '%s  image_local      ok    %s\n' "$name" "${digest:0:20}..."
        else
          printf '%s  image_local      missing   run eidolons mcp refresh %s\n' "$name" "$name"
          overall="degraded"
        fi
      else
        printf '%s  image_local      missing   no lockfile entry\n' "$name"
        overall="missing"
      fi

      # probes: mcp_uid_pin, mcp_bind_path_exists, mcp_bind_path_readable
      # Reads .mcp.json in CWD; silently no-ops if absent/malformed/no atlas-aci key.
      # The probe lines use err|warn|ok status words (separate from ok|degraded|missing).
      _mcp_driver_oci_uid_bind_probes "$name"

      # probe: registry_reachable (soft; if full_ref available)
      if [ -n "${full_ref:-}" ]; then
        local reg_rc=0
        atlas_aci_check_registry_reachable "$full_ref" 2>/dev/null || reg_rc=$?
        if [ "$reg_rc" -eq 0 ]; then
          printf '%s  registry_reachable  ok\n' "$name"
        else
          printf '%s  registry_reachable  degraded  ghcr.io unreachable or digest yanked\n' "$name"
          # registry unreachable is not fatal for OVERALL if image is local
        fi
      fi
    fi
  fi

  printf '%s  OVERALL          %s\n' "$name" "$overall"
}

# ─── binary driver ────────────────────────────────────────────────────────────
# These wrap the logic from cli/src/harness.sh without duplicating it.
# harness.sh functions (_harness_install, _harness_up, _harness_uninstall,
# _harness_verify) are still invoked from harness.sh for the legacy path.
# The driver functions here call the relevant harness.sh sub-functions by
# sourcing harness.sh and invoking them.

# _mcp_source_harness — source harness.sh once (idempotent).
_mcp_source_harness() {
  if [ -n "${_MCP_HARNESS_LOADED:-}" ]; then
    return 0
  fi
  _MCP_HARNESS_LOADED=1
  # shellcheck disable=SC1091
  . "$_LIB_MCP_DIR/harness.sh" || true
}

# mcp_driver_binary_install NAME VERSION [--force]
# Installs junction via its install.sh. Idempotent.
#
# TODO(FU1): promote algo: none → algo: sha256 once Junction install.sh publishes
# a binary digest. Track upstream at: https://github.com/Rynaro/Junction — when
# install.sh exposes a stable SHA-256 of the downloaded binary, wire it here and
# update the lockfile schema to require algo: sha256 for kind=binary in nexus v1.4.
mcp_driver_binary_install() {
  local name="$1"
  local version="$2"
  shift 2

  local force=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=true; shift ;;
      *)       shift ;;
    esac
  done

  # Strip version prefix if present (e.g. "0.2.0" or "v0.2.0").
  local ver="${version#v}"

  local cache_dir="${CACHE_DIR}/junction@${ver}"

  # Idempotency gate: if already installed and not --force, skip.
  if [ -d "$cache_dir" ]; then
    local existing_bin
    existing_bin=""
    if [ -x "$cache_dir/junction" ]; then
      existing_bin="$cache_dir/junction"
    elif [ -x "$cache_dir/bin/junction" ]; then
      existing_bin="$cache_dir/bin/junction"
    fi
    if [ -n "$existing_bin" ] && [ "$force" = "false" ]; then
      ok "junction@${ver} already installed at $existing_bin (use --force to reinstall)"
      # Still upsert lockfile in case it's missing.
      _mcp_binary_upsert_lock "$name" "$ver" "$cache_dir"
      return 0
    fi
    if [ "$force" = "true" ]; then
      rm -rf "$cache_dir"
    fi
  fi

  mkdir -p "$cache_dir"

  local install_url
  install_url="$(mcp_catalogue_get_field "$name" '.source.install_url')"
  if [ -z "$install_url" ]; then
    install_url="https://raw.githubusercontent.com/Rynaro/Junction/main/install.sh"
  fi

  say "Installing junction@${ver} into ${cache_dir}"

  if command -v curl >/dev/null 2>&1; then
    JUNCTION_INSTALL_DIR="$cache_dir" JUNCTION_VERSION="$ver" \
      bash <(curl -fsSL "$install_url") >/dev/null 2>&1 \
      || { rm -rf "$cache_dir"; die "Failed to install junction@${ver}."; }
  elif command -v wget >/dev/null 2>&1; then
    JUNCTION_INSTALL_DIR="$cache_dir" JUNCTION_VERSION="$ver" \
      bash <(wget -qO- "$install_url") >/dev/null 2>&1 \
      || { rm -rf "$cache_dir"; die "Failed to install junction@${ver}."; }
  else
    die "Neither curl nor wget found. Install one to bootstrap junction."
  fi

  local bin
  bin=""
  if [ -x "$cache_dir/junction" ]; then
    bin="$cache_dir/junction"
  elif [ -x "$cache_dir/bin/junction" ]; then
    bin="$cache_dir/bin/junction"
  fi
  if [ -z "$bin" ]; then
    rm -rf "$cache_dir"
    die "Junction install completed but binary not found in $cache_dir"
  fi

  ok "junction@${ver} installed at $bin"

  _mcp_binary_upsert_lock "$name" "$ver" "$cache_dir"
}

# _mcp_binary_upsert_lock NAME VERSION CACHE_DIR — write/update the lockfile
# entry for a binary MCP. Shared by install and refresh.
_mcp_binary_upsert_lock() {
  local name="$1" version="$2" cache_dir="$3"

  local source_repo installed_at target
  source_repo="$(mcp_catalogue_get_field "$name" '.source.repo')"
  installed_at="$(_mcp_now)"

  # Locate binary for target path.
  target=""
  if [ -x "$cache_dir/junction" ]; then
    target="$cache_dir/junction"
  elif [ -x "$cache_dir/bin/junction" ]; then
    target="$cache_dir/bin/junction"
  else
    target="$cache_dir"
  fi

  local hosts_wired='[".eidolons/harness/manifest.json"]'

  local entry
  entry="$(jq -n \
    --arg nm "$name" \
    --arg kd "binary" \
    --arg ver "$version" \
    --arg repo "$source_repo" \
    --arg tgt "$target" \
    --argjson hw "$hosts_wired" \
    --arg iat "$installed_at" \
    '{
      name: $nm,
      kind: $kd,
      version: $ver,
      source: {repo: $repo},
      integrity: {algo: "none", value: ""},
      target: $tgt,
      hosts_wired: $hw,
      installed_at: $iat
    }')"

  mcp_lock_upsert "$name" "$entry"
}

# mcp_driver_binary_refresh NAME VERSION
# Re-fetch the junction binary at the locked version. Updates installed_at.
mcp_driver_binary_refresh() {
  local name="$1"
  local version="${2:-}"

  # Prefer lockfile version if not specified.
  if [ -z "$version" ]; then
    version="$(mcp_lock_entry "$name" | jq -r '.version // empty')"
  fi
  if [ -z "$version" ]; then
    version="$(mcp_catalogue_get_field "$name" '.versions.pins.stable')"
  fi

  local ver="${version#v}"
  local cache_dir="${CACHE_DIR}/junction@${ver}"

  # Remove existing cache dir to force re-fetch.
  if [ -d "$cache_dir" ]; then
    rm -rf "$cache_dir"
  fi

  mcp_driver_binary_install "$name" "$ver" --force
}

# mcp_driver_binary_uninstall NAME
# Remove all junction@* cache dirs and the .eidolons/harness/ marker dir.
mcp_driver_binary_uninstall() {
  local name="$1"

  local entry
  entry="$(mcp_lock_entry "$name")"
  if [ -z "$entry" ]; then
    info "${name} not installed (nothing to remove)"
    return 0
  fi

  local dir
  for dir in "${CACHE_DIR}/junction@"*/; do
    if [ -d "$dir" ]; then
      rm -rf "${dir%/}"
      info "Removed cache: ${dir%/}"
    fi
  done

  if [ -d "./.eidolons/harness" ]; then
    rm -rf "./.eidolons/harness"
    info "Removed marker: .eidolons/harness"
  fi

  mcp_lock_remove "$name"
  ok "${name} uninstalled"
}

# mcp_driver_binary_version NAME → installed version to stdout (or empty).
mcp_driver_binary_version() {
  local name="$1"
  # Prefer lockfile.
  local ver
  ver="$(mcp_lock_entry "$name" | jq -r '.version // empty')"
  if [ -n "$ver" ]; then
    printf '%s\n' "$ver"
    return 0
  fi
  # Fallback: scan cache dir.
  local dir
  for dir in "${CACHE_DIR}/junction@"*/; do
    if [ -d "$dir" ]; then
      local base
      base="$(basename "${dir%/}")"
      printf '%s\n' "${base#junction@}"
      return 0
    fi
  done
}

# mcp_driver_binary_health NAME → probe status lines to stdout; exit 0 always.
mcp_driver_binary_health() {
  local name="$1"
  local overall="ok"

  # probe: binary_present
  local any_dir bin
  any_dir=""
  bin=""
  local d
  for d in "${CACHE_DIR}/junction@"*/; do
    if [ -d "$d" ]; then
      any_dir="${d%/}"
      break
    fi
  done

  if [ -z "$any_dir" ]; then
    printf '%s  binary_present   missing   run: eidolons mcp install %s\n' "$name" "$name"
    overall="missing"
  else
    if [ -x "$any_dir/junction" ]; then
      bin="$any_dir/junction"
    elif [ -x "$any_dir/bin/junction" ]; then
      bin="$any_dir/bin/junction"
    fi
    if [ -z "$bin" ]; then
      printf '%s  binary_present   missing   cache dir found but binary absent\n' "$name"
      overall="missing"
    else
      printf '%s  binary_present   ok    %s\n' "$name" "$bin"

      # probe: binary_version
      local bver=""
      bver="$("$bin" --version 2>/dev/null | head -1 || true)"
      if [ -n "$bver" ]; then
        printf '%s  binary_version   ok    %s\n' "$name" "$bver"
      else
        printf '%s  binary_version   degraded  could not get version\n' "$name"
        overall="degraded"
      fi
    fi
  fi

  # probe: docker_daemon_optional (soft warn, non-fatal)
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      printf '%s  docker_daemon_optional  ok\n' "$name"
    else
      printf '%s  docker_daemon_optional  degraded  Docker daemon unreachable (junction --no-container still works)\n' "$name"
      # Not fatal for OVERALL
    fi
  else
    printf '%s  docker_daemon_optional  degraded  Docker not found (junction --no-container still works)\n' "$name"
  fi

  printf '%s  OVERALL          %s\n' "$name" "$overall"
}

# ─── Generic dispatch helpers ─────────────────────────────────────────────────

# mcp_dispatch_driver KIND HOOK NAME [...]
# Calls mcp_driver_<kind>_<hook> with trailing args.
# KIND: oci-image | binary | script
# HOOK: install | refresh | uninstall | version | health
mcp_dispatch_driver() {
  local kind="$1" hook="$2" name="$3"
  shift 3

  # Convert kind to a valid bash function name component (replace '-' with '_').
  local kind_fn
  kind_fn="$(printf '%s' "$kind" | tr '-' '_')"

  local fn="mcp_driver_${kind_fn}_${hook}"
  if command -v "$fn" >/dev/null 2>&1 || type "$fn" >/dev/null 2>&1; then
    "$fn" "$name" "$@"
  else
    die "No driver for kind='$kind' hook='$hook'"
  fi
}

# mcp_resolve_kind NAME → emit kind from catalogue (or die).
mcp_resolve_kind() {
  local name="$1"
  local k
  k="$(mcp_catalogue_get_field "$name" '.kind')"
  if [ -z "$k" ]; then
    die "MCP '${name}' not found in catalogue. Try: eidolons mcp list"
  fi
  printf '%s\n' "$k"
}

# mcp_resolve_version NAME [requested_version]
# Resolve to a concrete version. If requested is empty or "@latest", use
# catalogue pins.stable. If in form "name@version", strip the name prefix.
mcp_resolve_version() {
  local name="$1"
  local requested="${2:-}"

  # Strip "name@version" form.
  case "$requested" in
    *@*)
      requested="${requested#*@}"
      ;;
  esac

  if [ -z "$requested" ] || [ "$requested" = "latest" ]; then
    mcp_catalogue_get_field "$name" '.versions.pins.stable'
  else
    printf '%s\n' "$requested"
  fi
}
